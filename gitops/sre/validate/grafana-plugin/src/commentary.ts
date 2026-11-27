import type { AssessmentState } from './api';

export interface Commentary {
  technical: string;
  layman: string;
}

export function describeAssessment(
  state: AssessmentState | null
): Commentary {
  if (!state) {
    return {
      technical: 'Controller telemetry unavailable.',
      layman: 'Waiting for a verified connection.',
    };
  }

  const scenario =
    state.profile === '1111'
      ? '11:11 Flash Sale'
      : 'Normal Sale';

  switch (state.state) {
    case 'idle':
      return {
        technical:
          'No active assessment is reserved.',
        layman:
          'The shop is awaiting a new test.',
      };

    case 'starting':
      return {
        technical:
          `${scenario}: assessment reserved. ` +
          'Production deployment, HPA and monitoring ' +
          'preflight checks are required before execution.',
        layman:
          'The system is preparing the test and checking ' +
          'whether the online shop is healthy.',
      };

    case 'running':
      return {
        technical:
          `${scenario}: the controller reports an active ` +
          'assessment. Consult k6 metrics to verify traffic.',
        layman:
          'The customer-demand test is underway.',
      };

    case 'recovering':
      return {
        technical:
          'Recovery observation is active. ' +
          'The controller evaluates fresh latency, ' +
          'failure-rate and request telemetry.',
        layman:
          'Customer demand is returning to normal. ' +
          'We are checking how quickly the shop stabilizes.',
      };

    case 'evaluating':
      return {
        technical:
          'The controller is evaluating the assessment ' +
          'outcome and recovery evidence.',
        layman:
          'The system is checking the final results.',
      };

    case 'finalizing':
      return {
        technical:
          'Assessment evidence is being archived before ' +
          'cleanup or the next eligible cycle.',
        layman:
          'The results are being saved.',
      };

    case 'stopping':
      return {
        technical:
          'Stop requested. The controller is terminating ' +
          'the active workload and disabling recurrence.',
        layman:
          'The test is being stopped.',
      };

    case 'stopped':
      return {
        technical:
          'Assessment stopped. Recovery is not automatically ' +
          'considered successful.',
        layman:
          'The test has stopped, but recovery still needs ' +
          'to be verified.',
      };

    case 'blocked':
      return {
        technical:
          'Execution blocked: ' +
          (state.last_error || 'Inspect controller state.'),
        layman:
          'The next test cannot safely proceed.',
      };

    default:
      return {
        technical:
          `Controller state: ${state.state}`,
        layman:
          'Waiting for further assessment information.',
      };
  }
}

export function describeRecovery(
  state: AssessmentState
): Commentary {
  if (
    state.recovery_outcome !== 'recovered' ||
    state.telemetry_valid !== true ||
    state.current_health_confirmed !== true ||
    typeof state.recovery_seconds !== 'number' ||
    !Number.isFinite(state.recovery_seconds) ||
    state.recovery_seconds < 0
  ) {
    return {
      technical:
        'Recovery has not been conclusively verified.',
      layman:
        'We do not yet have sufficient evidence that ' +
        'the shop has stabilized.',
    };
  }

  const seconds = Math.round(state.recovery_seconds);

  return {
    technical:
      `Measured recovery: ${seconds} seconds. ` +
      (state.recovery_target_met
        ? 'Five-minute recovery target achieved.'
        : 'Five-minute recovery target not achieved.'),
    layman:
      `The shop stabilized after approximately ` +
      `${seconds} seconds.`,
  };
}
