import React, { useMemo } from 'react';
import type { PanelProps } from '@grafana/data';

import { AssessmentAPI } from './api';
import { grafanaTransport } from './transport';
import { ControlPanel } from './ControlPanel';
import { BroadcastTicker } from './BroadcastTicker';
import { MetricExplanationGrid } from './MetricExplanationGrid';

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
    <main style={{
      width,
      height,
      overflow: 'auto',
      boxSizing: 'border-box',
    }}>
      <ControlPanel api={api} />
      <BroadcastTicker data={data} />
      <MetricExplanationGrid />
    </main>
  );
}
