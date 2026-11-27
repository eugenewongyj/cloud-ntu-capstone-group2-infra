import React from 'react';

import { MetricExplanation } from './MetricExplanation';
import { metricDefinitions } from './MetricDefinitions';

export function MetricExplanationGrid() {
  return (
    <section style={{ marginTop: 16 }}>
      <h3>Understanding the observability signals</h3>

      <p>
        Select an information button for the technical
        explanation, business meaning and metric source.
      </p>

      <div style={{
        display: 'grid',
        gridTemplateColumns:
          'repeat(auto-fit, minmax(240px, 1fr))',
        gap: 12,
      }}>
        {Object.entries(metricDefinitions).map(
          ([key, definition]) => (
            <article
              key={key}
              style={{
                padding: 12,
                border: '1px solid currentColor',
                borderRadius: 6,
              }}
            >
              <strong>{definition.title}</strong>
              {' '}
              <MetricExplanation {...definition} />

              <p>{definition.layman}</p>

              {'threshold' in definition && (
                <small>{definition.threshold}</small>
              )}
            </article>
          )
        )}
      </div>
    </section>
  );
}
