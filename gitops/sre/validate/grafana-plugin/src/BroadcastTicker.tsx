import React, { useEffect, useState } from 'react';
import type { PanelData } from '@grafana/data';
import {
  metricCatalogue,
  observe,
} from './BroadcastEngine';

type Event = {
  time: string;
  technical: string;
  layman: string;
};

export function BroadcastTicker({ data }: { data: PanelData }) {
  const [now, setNow] = useState(Date.now());
  const [mode, setMode] = useState('both');
  const [events, setEvents] = useState<Event[]>([]);

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);

  const observations = metricCatalogue.map(
    metric => observe(data, metric, now)
  );

  const warnings = observations.filter(
    item => item.severity === 'warning'
  );

  const ready = observations.find(
    item => item.metric.refId === 'H'
  )?.value;

  const desired = observations.find(
    item => item.metric.refId === 'I'
  )?.value;

  const available = observations.filter(
    item => item.value !== null
  ).length;

  const scaling = ready != null &&
    desired != null && desired > ready;

  const headline = warnings.length
    ? 'Customer objective threshold breached'
    : scaling
      ? 'Requested capacity exceeds ready capacity'
      : available === 0
        ? 'Awaiting verified telemetry'
        : 'Live infrastructure observations';

  const technical = warnings.length
    ? warnings.map(item => item.technical).join(' ')
    : scaling
      ? `${desired} replicas requested; ${ready} ready.`
      : `${available} of ${observations.length} metrics available.`;

  const layman = warnings.length
    ? 'Some shoppers may be experiencing degraded service.'
    : scaling
      ? 'Additional application workers are being prepared.'
      : available === 0
        ? 'Current system health cannot yet be confirmed.'
        : 'Monitoring is receiving infrastructure measurements.';

  useEffect(() => {
    setEvents(previous => {
      if (
        previous[0]?.technical === technical &&
        previous[0]?.layman === layman
      ) {
        return previous;
      }

      return [{
        time: new Date().toLocaleTimeString('en-SG', {
          timeZone: 'Asia/Singapore',
        }),
        technical,
        layman,
      }, ...previous].slice(0, 30);
    });
  }, [technical, layman]);

  return (
    <section style={{
      padding: 18,
      border: '1px solid #39566c',
      borderLeft: '4px solid #26a69a',
      borderRadius: 10,
      margin: 12,
    }}>
      <strong style={{ color: '#26a69a' }}>
        LIVE SRE BROADCAST
      </strong>

      <p>
        {new Date(now).toLocaleTimeString('en-SG', {
          timeZone: 'Asia/Singapore',
        })} SGT
      </p>

      <h2>{headline}</h2>

      <label>
        Commentary mode:{' '}
        <select value={mode}
          onChange={e => setMode(e.target.value)}>
          <option value="both">Technical + Layman</option>
          <option value="technical">Technical</option>
          <option value="layman">Layman</option>
        </select>
      </label>

      <div aria-live="polite">
        {mode !== 'layman' && (
          <p><strong>TECHNICAL:</strong> {technical}</p>
        )}
        {mode !== 'technical' && (
          <p><strong>PLAIN ENGLISH:</strong> {layman}</p>
        )}
      </div>

      <div style={{
        display: 'grid',
        gridTemplateColumns:
          'repeat(auto-fit, minmax(180px, 1fr))',
        gap: 10,
      }}>
        {observations.map(item => (
          <article key={item.metric.refId} style={{
            border: '1px solid #39566c',
            borderRadius: 8,
            padding: 12,
          }}>
            <small>{item.metric.title}</small>
            <div style={{
              fontSize: 26,
              fontWeight: 700,
              color: item.severity === 'warning'
                ? '#f59e0b'
                : item.severity === 'healthy'
                  ? '#26a69a'
                  : 'inherit',
            }}>
              {item.value === null
                ? 'Unavailable'
                : `${item.value.toFixed(2)} ${item.metric.unit}`}
            </div>
            {mode !== 'layman' && (
              <p>{item.technical}</p>
            )}
            {mode !== 'technical' && (
              <p>{item.layman}</p>
            )}
          </article>
        ))}
      </div>

      <h3>Broadcast event history</h3>
      <div style={{ maxHeight: 240, overflow: 'auto' }}>
        {events.map((event, index) => (
          <div key={`${event.time}-${index}`} style={{
            padding: 8,
            borderBottom: '1px solid #39566c',
          }}>
            <strong>{event.time} SGT</strong>
            {mode !== 'layman' && <p>{event.technical}</p>}
            {mode !== 'technical' && <p>{event.layman}</p>}
          </div>
        ))}
      </div>

      <small>
        Interval observations are not final assessment
        verdicts. Missing telemetry is not a pass.
      </small>
    </section>
  );
}
