const dashboards = {
  mission: 'capstone-retail-sre-live',
  k6: 'capstone-k6',
  hpa: 'capstone-hpa',
} as const;

export function dashboardLink(
  dashboard: keyof typeof dashboards,
  runId?: string,
  startedAt?: number
): string {
  const params = new URLSearchParams({
    'var-namespace': 'retail-store',
    refresh: '10s',
    from: 'now-30m',
    to: 'now',
  });

  if (
    dashboard !== 'hpa' &&
    runId &&
    /^[a-f0-9]{32}$/.test(runId)
  ) {
    params.set('var-assessment_run', runId);
  }

  if (
    typeof startedAt === 'number' &&
    Number.isFinite(startedAt) &&
    startedAt > 0
  ) {
    params.set(
      'from',
      String(Math.floor(startedAt * 1000) - 60000)
    );
  }

  return `/d/${dashboards[dashboard]}?${params.toString()}`;
}
