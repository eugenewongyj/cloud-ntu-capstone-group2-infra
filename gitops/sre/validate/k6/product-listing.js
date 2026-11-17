import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const path = __ENV.CAPSTONE_PRODUCT_PATH || '';
if (!path.startsWith('/') || path.startsWith('//')) throw new Error('Set CAPSTONE_PRODUCT_PATH to a verified path starting with one /');
const host = __ENV.TARGET_HOST || '';
if (!/^https?:\/\//.test(host)) throw new Error('Set TARGET_HOST to an approved staging URL');
const baseUsers = Number(__ENV.BASE_USERS || 1);
const profile = __ENV.LOAD_PROFILE || 'smoke';
if (!Number.isInteger(baseUsers) || baseUsers < 1 || baseUsers > 10) throw new Error('BASE_USERS must be 1–10 for this demo');
const profiles = {
  smoke: [{duration:'30s',target:1},{duration:'10s',target:0}],
  baseline: [{duration:'30s',target:baseUsers},{duration:'4m',target:baseUsers},{duration:'30s',target:0}],
  'flash-demo': [{duration:'30s',target:baseUsers},{duration:'1m30s',target:baseUsers},{duration:'1m',target:baseUsers*10},{duration:'2m',target:baseUsers*10},{duration:'1m',target:baseUsers*20},{duration:'2m',target:baseUsers*20},{duration:'1m',target:baseUsers},{duration:'1m',target:0}],
};
if (!profiles[profile]) throw new Error('Invalid LOAD_PROFILE');
if (profile === 'flash-demo' && __ENV.CAPSTONE_LOAD_APPROVED !== 'YES') throw new Error('Flash demo requires CAPSTONE_LOAD_APPROVED=YES after team approval');
const productLatency = new Trend('capstone_product_listing_duration', true);
const productFailure = new Rate('capstone_product_listing_failed');
export const options = {
  scenarios: { product_listing: { executor:'ramping-vus', startVUs:0, stages:profiles[profile], gracefulRampDown:'10s', gracefulStop:'15s' } },
  thresholds: {
    'http_req_duration{scenario:product_listing}':['p(95)<500'],
    'http_req_failed{scenario:product_listing}':['rate<0.01'],
    capstone_product_listing_failed:['rate<0.01'],
  },
  tags: { project:'Capstone', test_profile:profile },
  discardResponseBodies: false,
};
export default function () {
  const response = http.get(host.replace(/\/+$/,'') + path, {timeout:'10s',tags:{name:'product_listing'}});
  const marker = __ENV.CAPSTONE_EXPECT_TEXT || '';
  const ok = response.status >= 200 && response.status < 300 && (!marker || response.body.includes(marker));
  check(response, {'product_listing valid': () => ok});
  productLatency.add(response.timings.duration, {name:'product_listing'});
  productFailure.add(!ok, {name:'product_listing'});
  sleep(1 + Math.random()*2);
}
