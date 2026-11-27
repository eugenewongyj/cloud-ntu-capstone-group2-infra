import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Gauge } from 'k6/metrics';
import exec from 'k6/execution';

const path = __ENV.CAPSTONE_PRODUCT_PATH || '';
if (!path.startsWith('/') || path.startsWith('//')) throw new Error('Set CAPSTONE_PRODUCT_PATH to a verified path starting with one /');
const host = __ENV.TARGET_HOST || '';
if (host !== 'https://group2-shop.sctp-sandbox.com')
  throw new Error('Only the approved production host is permitted');
if (path !== '/catalog')
  throw new Error('Only the approved catalog path is permitted');
if (!/^[A-Za-z0-9_-]{1,64}$/.test(__ENV.ASSESSMENT_RUN || ''))
  throw new Error('A valid ASSESSMENT_RUN is required');
if (!/^https?:\/\//.test(host)) throw new Error('Set TARGET_HOST to an approved production URL');
const baseUsers = Number(__ENV.BASE_USERS || 1);
const profile = __ENV.LOAD_PROFILE || '';
const recoveryMinutes = Number(__ENV.RECOVERY_MINUTES || 10);
if (![5, 6, 7, 8, 9, 10].includes(recoveryMinutes))
  throw new Error('RECOVERY_MINUTES must be 5–10');
if (!Number.isInteger(baseUsers) || baseUsers < 1 || baseUsers > 10) throw new Error('BASE_USERS must be 1–10 for this demo');
const profiles = {
  normal: [
    {duration:'5m', target:baseUsers},
    {duration:`${recoveryMinutes}m`, target:baseUsers},
  ],
  '1111': [
    {duration:'30s', target:baseUsers*10},
    {duration:'60s', target:baseUsers*10},
    {duration:'30s', target:baseUsers*20},
    {duration:'150s', target:baseUsers*20},
    {duration:'30s', target:baseUsers},
    {duration:`${recoveryMinutes}m`, target:baseUsers},
  ],
};
if (!Object.hasOwn(profiles, profile)) throw new Error('Invalid LOAD_PROFILE');
const productLatency = new Trend('capstone_product_listing_duration', true);
const productFailure = new Rate('capstone_product_listing_failed');
const executionStart = new Gauge(
  'capstone_execution_start_seconds'
);

export const options = {
  scenarios: { product_listing: { executor:'ramping-vus', startVUs:baseUsers, stages:profiles[profile], gracefulRampDown:'10s', gracefulStop:'15s' } },
  thresholds: {
    'http_req_duration{scenario:product_listing}':['p(95)<500'],
    'http_req_failed{scenario:product_listing}':['rate<0.01'],
    capstone_product_listing_failed:['rate<0.01'],
  },
  tags: {
    project:'Capstone',
    test_profile:profile,
    namespace:'retail-store',
    assessment_run:__ENV.ASSESSMENT_RUN || 'unassigned',
  },
  discardResponseBodies: false,
};
const marker = __ENV.CAPSTONE_EXPECT_TEXT ||
  'These products are for demonstration purposes only';

export default function () {
  executionStart.add(
    exec.scenario.startTime / 1000
  );

  const elapsed = Date.now() - exec.scenario.startTime;
  const phase = elapsed >= 300000 ? 'recovery' : 'load';
  const response = http.get(host.replace(/\/+$/,'') + path, {timeout:'10s',redirects:0,tags:{name:'product_listing',assessment_phase:phase}});

  const ok = response.status >= 200 && response.status < 300 && (response.body || '').includes(marker);
  check(response, {'product_listing valid': () => ok});
  productLatency.add(response.timings.duration, {name:'product_listing',assessment_phase:phase});
  productFailure.add(!ok, {name:'product_listing',assessment_phase:phase});
  sleep(1 + Math.random()*2);
}
