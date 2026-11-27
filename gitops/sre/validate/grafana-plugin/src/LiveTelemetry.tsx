import React from 'react';
import type { PanelData } from '@grafana/data';

type Metric = {
  refId: string;
  name: string;
  unit: string;
  objective: string;
  technical: string;
  layman: string;
  healthy: (value: number) => boolean;
};

const metrics: Metric[] = [
  {
    refId: 'A',
    name: 'Product listing p95',
    unit: 'ms',
    objective: 'Below 500 ms',
    technical: 'Latest reported k6 product-listing p95 interval.',
    layman: 'How quickly most shoppers receive their product listing.',
    healthy: value => value < 500,
  },
  {
    refId: 'B',
    name: 'HTTP failure rate',
    unit: '%',
    objective: 'Below 1%',
    technical: 'Latest reported k6 HTTP failure-rate sample.',
    layman: 'How often simulated shoppers encounter failed requests.',
    healthy: value => value < 1,
  },
  {
    refId: 'C',
    name: 'Content failure rate',
    unit: '%',
    objective: 'Below 1%',
    technical: 'Latest catalog-content validation failure-rate sample.',
    layman: 'Whether shoppers receive the expected catalog page.',
    healthy: value => value < 1,
  },
];

function latest(
  data: PanelData,
  refId: string
): { value: number; time: number } | undefined {

  const frames = data.series.filter(
    frame => frame.refId === refId
  );

  // The query contract requires one aggregated series.
  if (frames.length !== 1) {
    return undefined;
  }

  const frame = frames[0];

  const numeric = frame.fields.find(
    field => field.type === 'number'
  );

  const time = frame.fields.find(
    field => field.type === 'time'
  );

  if (!numeric || !time) {
    return undefined;
  }

  const index = numeric.values.length - 1;

  if (index < 0) {
    return undefined;
  }

  const value = numeric.values[index];
  const timestamp = time.values[index];

  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    typeof timestamp !== 'number' ||
    !Number.isFinite(timestamp)
  ) {
    return undefined;
  }

  return {
    value,
    time: timestamp,
  };
}

export function LiveTelemetry(
  { data }: { data: PanelData }
) {
  const [technical, setTechnical] = React.useState(true);

  return (
    <section style={{
      padding: 12,
      border: '1px solid currentColor',
      borderRadius: 6,
      marginTop: 12,
    }}>
      <h3>Assessment telemetry commentary</h3>

      <button
        type="button"
        onClick={() => setTechnical(!technical)}
      >
        {technical
          ? 'Show layman explanation'
          : 'Show technical explanation'}
      </button>

      <p>
        Samples describe observed metrics, not a final
        assessment or recovery verdict.
      </p>

      {metrics.map(metric => {
        const sample = latest(data, metric.refId);

        const age = sample
          ? Date.now() - sample.time
          : Infinity;

        const fresh = age >= -5000 && age <= 30000;

        return (
          <article
            key={metric.refId}
            style={{
              padding: 10,
              marginTop: 8,
              border: '1px solid currentColor',
              borderRadius: 4,
            }}
          >
            <strong>{metric.name}</strong>

            <p>
              {sample
                ? `${sample.value.toFixed(2)} ${metric.unit}`
                : 'Telemetry unavailable'}
            </p>

            <p>Objective: {metric.objective}</p>

            <p>
              {!sample
                ? 'Waiting for assessment data.'
                : !fresh
                  ? 'Historical or stale sample.'
                  : metric.healthy(sample.value)
                    ? 'Latest sample meets objective.'
                    : 'Latest sample breaches objective.'}
            </p>

            <p>
              {technical
                ? metric.technical
                : metric.layman}
            </p>

            {sample && (
              <small>
                Sample: {
                  new Date(sample.time).toLocaleString(
                    'en-SG',
                    { timeZone: 'Asia/Singapore' }
                  )
                }
              </small>
            )}
          </article>
        );
      })}
    </section>
  );
}
