import type { PanelData } from '@grafana/data';

export type Severity =
  'healthy' | 'warning' | 'critical' | 'unknown';

export interface BroadcastMetric {
  refId: string;
  title: string;
  unit: string;
  technical: string;
  layman: string;
  threshold?: number;
}

export interface Observation {
  metric: BroadcastMetric;
  value: number | null;
  timestamp: number | null;
  severity: Severity;
  technical: string;
  layman: string;
}

export const metricCatalogue: BroadcastMetric[] = [
  {
    refId: 'A',
    title: 'Product listing p95',
    unit: 'ms',
    threshold: 500,
    technical: 'Latest k6 product-listing p95 interval.',
    layman: 'How quickly most shoppers receive the catalog page.',
  },
  {
    refId: 'B',
    title: 'HTTP failure rate',
    unit: '%',
    threshold: 1,
    technical: 'Observed k6 HTTP request failure rate.',
    layman: 'How often shoppers encounter failed requests.',
  },
  {
    refId: 'C',
    title: 'Content failure rate',
    unit: '%',
    threshold: 1,
    technical: 'Observed catalog content validation failure rate.',
    layman: 'Whether shoppers receive the expected product page.',
  },
  {
    refId: 'D',
    title: 'Request throughput',
    unit: 'req/s',
    technical: 'Rate of increase in the k6 request counter.',
    layman: 'How many requests the store handles each second.',
  },
  {
    refId: 'E',
    title: 'Virtual users',
    unit: 'VU',
    technical: 'Active concurrent k6 virtual users.',
    layman: 'How many simulated shoppers are currently active.',
  },
  {
    refId: 'F',
    title: 'Production CPU',
    unit: 'cores',
    technical: 'Aggregate container CPU consumption.',
    layman: 'How much processing power the store is using.',
  },
  {
    refId: 'G',
    title: 'Production memory',
    unit: 'MiB',
    technical: 'Aggregate container memory working set.',
    layman: 'How much working memory the application requires.',
  },
  {
    refId: 'H',
    title: 'Ready replicas',
    unit: 'pods',
    technical: 'Ready production deployment replicas.',
    layman: 'Workers ready to serve customers.',
  },
  {
    refId: 'I',
    title: 'Desired replicas',
    unit: 'pods',
    technical: 'Desired production deployment replicas.',
    layman: 'Workers requested by the infrastructure.',
  },
  {
    refId: 'J',
    title: 'Pending pods',
    unit: 'pods',
    technical: 'Production pods in Pending phase.',
    layman: 'Workers waiting to become available.',
  },
  {
    refId: 'K',
    title: 'Ready nodes',
    unit: 'nodes',
    technical: 'Kubernetes nodes reporting Ready.',
    layman: 'Servers available to run application workloads.',
  },
  {
    refId: 'L',
    title: 'Recent container restarts',
    unit: 'restarts',
    technical: 'Container restart counter increase over five minutes.',
    layman: 'How often application containers recently restarted.',
  },
  {
    refId: 'M',
    title: 'Firing production alerts',
    unit: 'alerts',
    technical: 'Prometheus alerts currently in firing state.',
    layman: 'Active monitoring warnings requiring attention.',
  },
];

export function observe(
  data: PanelData,
  metric: BroadcastMetric,
  now = Date.now()
): Observation {
  const frames = data.series.filter(
    frame => frame.refId === metric.refId
  );

  const unknown = (
    reason: string
  ): Observation => ({
    metric,
    value: null,
    timestamp: null,
    severity: 'unknown',
    technical: reason,
    layman: 'Current measurement cannot be confirmed.',
  });

  if (frames.length !== 1) {
    return unknown('Expected one aggregated telemetry series.');
  }

  const numeric = frames[0].fields.find(
    field => field.type === 'number'
  );

  const time = frames[0].fields.find(
    field => field.type === 'time'
  );

  if (!numeric || !time || !numeric.values.length) {
    return unknown('No telemetry sample available.');
  }

  const index = numeric.values.length - 1;
  const value = numeric.values[index];
  const timestamp = time.values[index];

  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    typeof timestamp !== 'number' ||
    !Number.isFinite(timestamp)
  ) {
    return unknown('Invalid telemetry sample.');
  }

  if (now - timestamp > 45000 || timestamp > now + 5000) {
    return unknown('Telemetry is stale or historical.');
  }

  const breached = metric.threshold !== undefined &&
    (metric.refId === 'A'
      ? value > metric.threshold
      : value >= metric.threshold);

  return {
    metric,
    value,
    timestamp,
    severity: breached
      ? 'warning'
      : metric.threshold === undefined
        ? 'unknown'
        : 'healthy',
    technical:
      `${metric.title}: ${value.toFixed(2)} ${metric.unit}. ` +
      metric.technical +
      (breached ? ' Objective breached.' : ''),
    layman: metric.layman +
      (breached
        ? ' The measured value exceeds the objective.'
        : ''),
  };
}
