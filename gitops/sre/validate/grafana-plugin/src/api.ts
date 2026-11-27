export type Profile = 'normal' | '1111';

export interface StartRequest {
  profile: Profile;
  base_users: number;
  recovery_minutes: number;
  repeat: boolean;
  max_cycles: number;
}

export interface AssessmentState {
  state: string;
  assessment_run: string | null;
  profile: Profile | null;
  base_users: number;
  recovery_minutes: number;
  repeat: boolean;
  cycle: number;
  max_cycles: number;
  stop_requested: boolean;
  started_at: number | null;
  execution_started_at?: number | null;
  recovery_started_at: number | null;
  recovery_seconds: number | null;
  recovery_target_met?: boolean;
  recovery_outcome?: string;
  current_health_confirmed?: boolean;
  telemetry_valid?: boolean;
  job_outcome?: string;
  last_error: string | null;
  last_completed_run: string | null;
  latest_metrics?: Record<string, unknown>;
  preflight?: {
    healthy: boolean;
    failed_checks?: string[];
  };
  history: Record<string, unknown>[];
}

export type Transport = <T>(
  method: 'GET' | 'POST',
  path: string,
  body?: unknown
) => Promise<T>;

export class AssessmentAPI {
  constructor(private readonly transport: Transport) {}

  status(): Promise<AssessmentState> {
    return this.transport(
      'GET',
      '/api/v1/status'
    );
  }

  history(): Promise<{
    assessments: Record<string, unknown>[];
  }> {
    return this.transport(
      'GET',
      '/api/v1/history'
    );
  }

  start(request: StartRequest): Promise<AssessmentState> {
    if (!['normal', '1111'].includes(request.profile)) {
      throw new Error('Unsupported assessment profile');
    }

    if (request.base_users !== 1) {
      throw new Error('Production baseline is limited to 1 VU');
    }

    if (
      !Number.isInteger(request.recovery_minutes) ||
      request.recovery_minutes < 5 ||
      request.recovery_minutes > 10
    ) {
      throw new Error('Recovery must be 5–10 minutes');
    }

    if (
      !Number.isInteger(request.max_cycles) ||
      request.max_cycles < 1 ||
      request.max_cycles > 3
    ) {
      throw new Error('Maximum three assessment cycles');
    }

    return this.transport(
      'POST',
      '/api/v1/start',
      request
    );
  }

  stop(runId: string): Promise<AssessmentState> {
    if (!/^[a-f0-9]{32}$/.test(runId)) {
      throw new Error('Invalid assessment identity');
    }

    return this.transport(
      'POST',
      '/api/v1/stop',
      { assessment_run: runId }
    );
  }
}
