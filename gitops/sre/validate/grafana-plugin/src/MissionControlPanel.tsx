import { MetricExplanationGrid } from './MetricExplanationGrid';
import { LiveTelemetry } from './LiveTelemetry';
import React, { useMemo } from 'react';

import type { PanelProps } from '@grafana/data';

import { AssessmentAPI } from './api';
import { grafanaTransport } from './transport';
import { ControlPanel } from './ControlPanel';

export function MissionControlPanel({
  width,
  height,
  data,
}: PanelProps) {
  const api = useMemo(
    () => new AssessmentAPI(grafanaTransport),
    []
  );

  return (
    <div style={{
      width,
      height,
      overflow: 'auto',
      boxSizing: 'border-box',
    }}>
      <ControlPanel api={api} />
      <LiveTelemetry data={data} />
      <MetricExplanationGrid />
    </div>
  );
}
