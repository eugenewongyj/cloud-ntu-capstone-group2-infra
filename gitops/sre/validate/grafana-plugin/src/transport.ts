import { getBackendSrv } from '@grafana/runtime';
import type { Transport } from './api';

const RESOURCE_BASE =
  '/api/plugins/capstone-srecontrol-app/resources';

const allowed = new Set([
  'GET /api/v1/status',
  'GET /api/v1/history',
  'POST /api/v1/start',
  'POST /api/v1/stop',
]);

export const grafanaTransport: Transport =
  async <T>(
    method: 'GET' | 'POST',
    path: string,
    body?: unknown
  ): Promise<T> => {
    if (!allowed.has(`${method} ${path}`)) {
      throw new Error('Unsupported operation');
    }

    const response =
      await getBackendSrv().datasourceRequest({
        url: `${RESOURCE_BASE}${path}`,
        method,
        data: body,
        headers: {
          'Content-Type': 'application/json',
        },
      });

    return response.data as T;
  };
