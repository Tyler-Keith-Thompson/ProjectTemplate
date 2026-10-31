// The server's load test, run by k6 (https://grafana.com/docs/k6/) through `just load`.
//
// It ramps up to 50 virtual users, holds them, and ramps back down. Each user calls every route in
// turn, then waits a second, as a client would; `just load --vus 200 --duration 30s` pushes harder.
// The thresholds below are the pass mark: k6 exits non-zero when one fails. Requests go to
// BASE_URL, which `just load` sets to the production image it starts.
import http from 'k6/http';
import { check, sleep } from 'k6';

const baseURL = __ENV.BASE_URL || 'http://localhost:8080';

export const options = {
    scenarios: {
        ramp: {
            executor: 'ramping-vus',
            stages: [
                { duration: '10s', target: 50 },
                { duration: '30s', target: 50 },
                { duration: '10s', target: 0 },
            ],
        },
    },
    thresholds: {
        http_req_failed: ['rate<0.01'],
        http_req_duration: ['p(95)<100', 'p(99)<250'],
        // One per route, so a failure names the route that regressed.
        'http_req_duration{name:GET /health}': ['p(95)<100'],
        'http_req_duration{name:GET /hello/:name}': ['p(95)<100'],
        // database:begin
        'http_req_duration{name:GET /hello/:name/count}': ['p(95)<100'],
        // database:end
        checks: ['rate>0.99'],
    },
};

const names = ['Ada', 'Grace', 'Edsger', 'Barbara', 'Donald'];

export default function () {
    const name = names[(__VU + __ITER) % names.length];

    const health = http.get(`${baseURL}/health`, { tags: { name: 'GET /health' } });
    check(health, { 'health answers ok': (response) => response.status === 200 && response.body === 'ok' });

    const hello = http.get(`${baseURL}/hello/${name}`, { tags: { name: 'GET /hello/:name' } });
    check(hello, { 'hello greets the name': (response) => response.status === 200 && response.body === `Good day, ${name}!` });
    // database:begin

    const count = http.get(`${baseURL}/hello/${name}/count`, { tags: { name: 'GET /hello/:name/count' } });
    check(count, { 'count is a positive number': (response) => response.status === 200 && Number(response.body) > 0 });
    // database:end

    sleep(1);
}
