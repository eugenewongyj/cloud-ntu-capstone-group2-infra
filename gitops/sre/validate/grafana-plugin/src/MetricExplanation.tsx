import React, { useId, useState } from 'react';

interface MetricExplanationProps {
  title: string;
  technical: string;
  layman: string;
  query: string;
  threshold?: string;
}

export function MetricExplanation({
  title,
  technical,
  layman,
  query,
  threshold,
}: MetricExplanationProps) {
  const [hovered, setHovered] = useState(false);
  const [pinned, setPinned] = useState(false);
  const id = useId();
  const visible = hovered || pinned;

  return (
    <span
      style={{ position: 'relative', display: 'inline-block' }}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onKeyDown={(event) => {
        if (event.key === 'Escape') {
          setPinned(false);
          setHovered(false);
        }
      }}
    >
      <button
        type="button"
        aria-label={`Explain ${title}`}
        aria-expanded={visible}
        aria-controls={id}
        onFocus={() => setHovered(true)}
        onBlur={() => setHovered(false)}
        onClick={() => setPinned(!pinned)}
        style={{
          background: 'transparent',
          border: '1px solid currentColor',
          borderRadius: '50%',
          color: 'inherit',
          cursor: 'help',
          width: 24,
          height: 24,
        }}
      >
        i
      </button>

      {visible && (
        <div
          id={id}
          role="region"
          aria-label={`${title} explanation`}
          style={{
            position: 'absolute',
            top: '100%',
            right: 0,
            zIndex: 1000,
            width: 340,
            maxWidth: '80vw',
            padding: 16,
            background: '#181b1f',
            color: '#f4f5f5',
            border: '1px solid #52545c',
            borderRadius: 8,
            boxShadow: '0 8px 24px #0006',
            overflowWrap: 'anywhere',
          }}
        >
          <h4>{title}</h4>

          <strong>Technical explanation</strong>
          <p>{technical}</p>

          <strong>In simple terms</strong>
          <p>{layman}</p>

          {threshold && (
            <>
              <strong>Assessment threshold</strong>
              <p>{threshold}</p>
            </>
          )}

          <strong>PromQL / metric source</strong>
          <pre style={{ whiteSpace: 'pre-wrap' }}>
            {query}
          </pre>

          <small>
            Click the information button to pin or unpin.
            Press Escape to dismiss.
          </small>
        </div>
      )}
    </span>
  );
}
