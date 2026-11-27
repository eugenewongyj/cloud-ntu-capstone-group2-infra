import { locationService } from '@grafana/runtime';
import React, {
  useEffect,
  useRef,
  useState,
} from 'react';

import {
  AssessmentAPI,
  AssessmentState,
  Profile,
} from './api';

import {
  describeAssessment,
  describeRecovery,
} from './commentary';

import { dashboardLink } from './dashboardLinks';

interface Props {
  api: AssessmentAPI;
}

const POLL_INTERVAL_MS = 5000;

const STOPPABLE = new Set([
  'starting',
  'running',
  'recovering',
  'evaluating',
  'finalizing',
]);

export function ControlPanel({ api }: Props) {
  const [state, setState] =
    useState<AssessmentState | null>(null);

  const [connected, setConnected] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');

  const [recovery, setRecovery] = useState(10);
  const [repeat, setRepeat] = useState(false);
  const [cycles, setCycles] = useState(3);

  const [updatedAt, setUpdatedAt] =
    useState<number | null>(null);

  const requestLock = useRef(false);
  const sequence = useRef(0);

  useEffect(() => {
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout>;

    async function poll() {
      const requestId = ++sequence.current;

      try {
        const result = await api.status();

        if (
          !cancelled &&
          requestId === sequence.current
        ) {
          setState(result);
          setConnected(true);
          setUpdatedAt(Date.now());
        }
      } catch {
        if (
          !cancelled &&
          requestId === sequence.current
        ) {
          setConnected(false);
        }
      } finally {
        if (!cancelled) {
          timer = setTimeout(
            poll,
            POLL_INTERVAL_MS
          );
        }
      }
    }

    void poll();

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [api]);

  const idle =
    connected &&
    state?.state === 'idle' &&
    !pending;

  async function execute(
    operation: () => Promise<AssessmentState>
  ) {
    if (requestLock.current) {
      return;
    }

    requestLock.current = true;
    setPending(true);
    setError('');

    ++sequence.current;

    try {
      await operation();

      const requestId = ++sequence.current;
      const result = await api.status();

      if (requestId === sequence.current) {
        setState(result);
        setConnected(true);
        setUpdatedAt(Date.now());
      }
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : 'Controller request failed'
      );
      setConnected(false);
    } finally {
      requestLock.current = false;
      setPending(false);
    }
  }

  function start(profile: Profile) {
    if (!idle) {
      return;
    }

    void execute(() =>
      api.start({
        profile,
        base_users: 1,
        recovery_minutes: recovery,
        repeat,
        max_cycles: repeat ? cycles : 1,
      })
    );
  }

  function stop(profile: Profile) {
    if (
      !connected ||
      !state?.assessment_run ||
      state.profile !== profile ||
      !STOPPABLE.has(state.state)
    ) {
      return;
    }

    const runId = state.assessment_run;

    void execute(() => api.stop(runId));
  }


  // Follow the controller's authoritative active run.
  // Grafana re-evaluates dashboard queries when the
  // assessment_run template variable changes.
  useEffect(() => {
    const activeRun = state?.assessment_run;

    if (
      !connected ||
      !activeRun ||
      !/^[a-f0-9]{32}$/.test(activeRun)
    ) {
      return;
    }

    const location = locationService.getLocation();

    const params = new URLSearchParams(
      location.search
    );

    if (
      params.get('var-assessment_run') === activeRun &&
      params.get('var-namespace') === 'retail-store'
    ) {
      return;
    }

    locationService.partial({
      'var-assessment_run': activeRun,
      'var-namespace': 'retail-store',
      refresh: '10s',
    }, true);

  }, [connected, state?.assessment_run]);

  const commentary = describeAssessment(
    connected ? state : null
  );

  const recoveryCommentary =
    connected && state
      ? describeRecovery(state)
      : null;

  const runId =
    state?.assessment_run ||
    state?.last_completed_run ||
    undefined;

  return (
    <section style={{ padding: 16 }}>
      <h2>Capstone — Retail SRE Mission Control</h2>

      <p>
        Production: retail-store |
        Controller: {connected ? 'Connected' : 'Unavailable'}
      </p>

      <p>
        State: {
          connected
            ? state?.state ?? 'unknown'
            : 'unknown'
        }
      </p>

      <p>
        Last successful update: {
          updatedAt
            ? new Date(updatedAt).toLocaleTimeString()
            : 'Unavailable'
        }
      </p>

      {error && (
        <p role="alert">{error}</p>
      )}

      <fieldset disabled={!idle}>
        <legend>Assessment configuration</legend>

        <label>
          Recovery observation:
          <select
            value={recovery}
            onChange={e =>
              setRecovery(Number(e.target.value))
            }
          >
            {[5, 6, 7, 8, 9, 10].map(value => (
              <option key={value} value={value}>
                {value} minutes
              </option>
            ))}
          </select>
        </label>

        <p>
          <label>
            <input
              type="checkbox"
              checked={repeat}
              onChange={e =>
                setRepeat(e.target.checked)
              }
            />
            Automatically repeat after verified recovery
          </label>
        </p>

        {repeat && (
          <label>
            Maximum cycles:
            <select
              value={cycles}
              onChange={e =>
                setCycles(Number(e.target.value))
              }
            >
              {[1, 2, 3].map(value => (
                <option key={value} value={value}>
                  {value}
                </option>
              ))}
            </select>
          </label>
        )}
      </fieldset>

      <div style={{
        display: 'grid',
        gridTemplateColumns:
          'repeat(auto-fit, minmax(240px, 1fr))',
        gap: 16,
        marginTop: 16,
      }}>
        {([
          ['normal', 'Normal Sale', 1],
          ['1111', '11:11 Flash Sale', 20],
        ] as const).map(([profile, title, peak]) => (
          <section
            key={profile}
            style={{
              border: '1px solid #64748b',
              borderRadius: 8,
              padding: 16,
            }}
          >
            <h3>{title}</h3>

            <p>Baseline: 1 virtual user</p>
            <p>Peak: {peak} virtual users</p>
            <p>Load duration: 5 minutes</p>

            <p>
              {profile === 'normal'
                ? 'Establish normal operating performance.'
                : 'Increase demand to 10x and 20x baseline.'}
            </p>

            <button
              disabled={!idle}
              onClick={() => start(profile)}
            >
              Start
            </button>

            {' '}

            <button
              disabled={
                pending ||
                !connected ||
                state?.profile !== profile ||
                !STOPPABLE.has(state?.state ?? '')
              }
              onClick={() => stop(profile)}
            >
              Stop
            </button>
          </section>
        ))}
      </div>

      <section
        aria-live="polite"
        style={{ marginTop: 24 }}
      >
        <h3>Live assessment commentary</h3>

        <strong>Technical explanation</strong>
        <p>{commentary.technical}</p>

        <strong>Layman explanation</strong>
        <p>{commentary.layman}</p>

        {connected && state?.assessment_run && (
          <>
            <p>Assessment: {state.assessment_run}</p>
            <p>
              Cycle: {state.cycle} / {state.max_cycles}
            </p>
          </>
        )}

        {connected &&
          state?.preflight?.healthy === false && (
          <p role="alert">
            Failed preflight checks: {
              state.preflight.failed_checks?.join(', ')
                || 'Inspect controller status'
            }
          </p>
        )}

        {recoveryCommentary && (
          <>
            <h4>Recovery evidence</h4>
            <p>{recoveryCommentary.technical}</p>
            <p>{recoveryCommentary.layman}</p>
          </>
        )}
      </section>

      <nav style={{ marginTop: 24 }}>
        <h3>Live infrastructure dashboards</h3>

        <a href={dashboardLink('mission', runId)}>
          Mission Control
        </a>

        {' | '}

        <a href={dashboardLink('k6', runId)}>
          k6 Performance
        </a>

        {' | '}

        <a href={dashboardLink('hpa')}>
          HPA and Autoscaling
        </a>
      </nav>
    </section>
  );
}
