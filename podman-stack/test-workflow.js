export const meta = {
  name: 'vibe-kanban-full-test',
  description: 'Team test of a self-hosted vibe-kanban stack (6 domains + resilience), scored',
  phases: [
    { title: 'Functional', detail: '6 parallel domain testers' },
    { title: 'Resilience', detail: 'restart each service, verify self-heal' },
  ],
}

// ---- args(必填):部署環境存取內容 ----
// Workflow 呼叫範例:
// Workflow({scriptPath: ".../test-workflow.js", args: {
//   ssh: "sshpass -p <pw> ssh -o StrictHostKeyChecking=accept-new <user>@<host>",
//   remoteUrl: "https://<remote-domain>", relayUrl: "https://<relay-domain>",
//   email: "<localauth-email>", password: "<localauth-password>",
//   stackDir: "~/vibe-kanban-stack", hostPort: 3000, uid: 1000,
//   protectedContainers: "cf-tunnel-webgui, homeassistant, immich*, n8n, ..." }})
const A = args || {}
if (!A.ssh || !A.remoteUrl) throw new Error('args.ssh and args.remoteUrl required')

const ACCESS = `
## Target system access (user's OWN infra; you are authorized)
- Remote commands:  ${A.ssh} '<remote bash>'
- For systemctl --user / journalctl --user prefix remote bash with: export XDG_RUNTIME_DIR=/run/user/${A.uid ?? 1000};
- Public URLs: remote=${A.remoteUrl}  relay=${A.relayUrl}
- Host local UI on the box: http://127.0.0.1:${A.hostPort ?? 3000} (ssh only)
- localAuth: ${A.email} / ${A.password}
- Bearer token: TOK=$(curl -s -X POST ${A.remoteUrl}/v1/auth/local/login -H 'Content-Type: application/json' -d '{"email":"${A.email}","password":"${A.password}"}' | jq -r .access_token)
- Stack dir: ${A.stackDir ?? '~/vibe-kanban-stack'} ; containers <proj>_remote-db_1, _remote-server_1, _electric_1, _relay-server_1 ; host unit vibe-kanban-host.service

## Rules
- Prefer read-only. Created data must be prefixed "ZZZ-test-" and DELETED at the end.
- NEVER touch these containers/services: ${A.protectedContainers ?? '(any container not part of the vibe-kanban stack)'}
- Concrete EVIDENCE (output/HTTP codes/json) for every check. Honest pass/fail/warn.
`

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    domain: { type: 'string' },
    checks: { type: 'array', items: { type: 'object', additionalProperties: false,
      properties: { name: {type:'string'}, status: {type:'string', enum:['pass','fail','warn']},
        severity: {type:'string', enum:['critical','high','medium','low']}, evidence: {type:'string'} },
      required: ['name','status','evidence'] } },
    summary: { type: 'string' },
  }, required: ['domain','checks','summary'],
}

const DOMAINS = [
  { key: 'infra-db-electric', prompt: `Test INFRA+POSTGRES+ELECTRIC: 4 containers Up/healthy; restart policy always; wal_level=logical; electric_sync role LOGIN+REPLICATION + publication electric_publication_default; electric logs replicating with no errors; named volumes mounted; service ports bound to 127.0.0.1 only unless LAN intentionally enabled; podman stats snapshot.` },
  { key: 'auth', prompt: `Test AUTH: /v1/auth/methods local only; correct creds -> 200 + both tokens; wrong password -> 401 no token; /v1/hosts without token -> 401, with valid -> 200, with garbage bearer -> 401; host /api/auth/status + /api/auth/methods; access_token is 3-part HS256 JWT.` },
  { key: 'cloud-api-crud', prompt: `Test CLOUD API CRUD via edge with fresh TOK: /v1/health; list orgs; create ZZZ-test-org -> verify -> create ZZZ-test project/workspace if endpoints exist -> verify; DELETE everything ZZZ-test and verify gone. Never touch the user's personal org. Discover real routes from <stackDir>/src/crates/remote/src/routes if a guess 404s.` },
  { key: 'relay-remote-access', prompt: `Test RELAY: relay /health via edge + on box; /v1/hosts lists the host online with owner access; relay container logs clean; host logged_in true (if not, login via POST 127.0.0.1:<hostPort>/api/auth/local/login and confirm it re-registers online); ws upgrade at relay /v1/relay/connect returns 101/4xx not 000/502; note single-hostname (no wildcard) suffices.` },
  { key: 'host-executor', prompt: `Test HOST+EXECUTOR on box: host unit active; UI 200 with title; /api/info shared_api_base = self-hosted remote (NOT api.vibekanban.com); claude CLI authenticated (timeout 25 claude -p "reply exactly READY" --max-turns 1); journal shows CLAUDE_CODE executor; git available. Optionally (warn not fail if too involved): create throwaway git repo + POST /api/repos + POST /api/workspaces/start with executor CLAUDE_CODE and a trivial file-creation prompt, verify the file + commit appear in /var/tmp/vibe-kanban/worktrees/..., then archive/delete workspace + repo + rm -rf.` },
  { key: 'edge-security', prompt: `Test EDGE/SECURITY: remote /v1/health + / (title) + relay /health via CF edge; ALL pre-existing tunnel routes still work (list from tunnel backup json; 502 on a route whose backend was already down is not collateral — verify against backup); TLS via CF; .env and any *credential* files mode 600 with no real secrets in world-readable files (.env.example must contain only placeholders); DNS CNAMEs resolve.` },
]

phase('Functional')
const functional = await parallel(
  DOMAINS.map((d) => () =>
    agent(`${ACCESS}\n\nYou are a QA tester. ${d.prompt}\n\nReturn structured findings. domain="${d.key}".`,
      { label: `test:${d.key}`, phase: 'Functional', schema: SCHEMA }))
)

phase('Resilience')
const resilience = await agent(
  `${ACCESS}
You are the RESILIENCE tester. SEQUENTIALLY (restore full state at the end; ONLY touch the vibe-kanban stack containers + vibe-kanban-host unit):
1. restart remote-db -> remote /v1/health recovers (restart:always self-heal).
2. restart electric -> logs show replication restored.
3. restart relay -> /health 200 and host back online in /v1/hosts within ~90s.
4. systemctl --user restart vibe-kanban-host -> auto re-login from persisted credentials.json + online WITHOUT manual login (key durability proof).
5. persistence: pg data survives; host db.v2.sqlite + credentials.json present.
6. FINAL: all containers Up/healthy + host online; if not, bring up via start.sh and re-verify.
Return structured findings. domain="resilience".`,
  { label: 'test:resilience', phase: 'Resilience', schema: SCHEMA })

const all = [...functional.filter(Boolean), resilience].filter(Boolean)
let pass = 0, fail = 0, warn = 0
const failures = []
for (const r of all) for (const c of (r.checks || [])) {
  if (c.status === 'pass') pass++
  else if (c.status === 'warn') warn++
  else { fail++; failures.push({ domain: r.domain, name: c.name, severity: c.severity || 'unknown', evidence: c.evidence }) }
}
const total = pass + fail
return { score: total ? Math.round((pass/total)*100) : 0, totals: {pass, fail, warn, total}, failures,
  domains: all.map(r => ({ domain: r.domain, summary: r.summary, checks: r.checks })) }
