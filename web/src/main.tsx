import { render } from "preact";
import { useEffect, useMemo, useState } from "preact/hooks";
import { api, post, setCSRF } from "./api";
import type { Job, Overview, Repository, Run, Snapshot } from "./types";
import "./styles.css";

type View = "overview" | "jobs" | "runs" | "snapshots" | "settings";

const emptyRetention = { last: 7, hourly: 0, daily: 7, weekly: 4, monthly: 6 };

function App() {
  const [boot, setBoot] = useState<"loading" | "setup" | "login" | "ready">("loading");
  const [view, setView] = useState<View>("overview");
  const [repos, setRepos] = useState<Repository[]>([]);
  const [jobs, setJobs] = useState<Job[]>([]);
  const [runs, setRuns] = useState<Run[]>([]);
  const [overview, setOverview] = useState<Overview | null>(null);
  const [error, setError] = useState("");

  async function loadAll() {
    try {
      const [repoData, jobData, runData, overviewData] = await Promise.all([
        api<Repository[]>("/repositories"), api<Job[]>("/jobs"), api<Run[]>("/runs"), api<Overview>("/overview"),
      ]);
      setRepos(repoData || []); setJobs(jobData || []); setRuns(runData || []); setOverview(overviewData);
    } catch (err) { setError(message(err)); }
  }

  useEffect(() => {
    api<{ setup_required: boolean }>("/setup")
      .then(async ({ setup_required }) => {
        if (setup_required) { setBoot("setup"); return; }
        try {
          const session = await api<{ csrf_token: string }>("/session");
          setCSRF(session.csrf_token); setBoot("ready"); await loadAll();
        } catch { setBoot("login"); }
      })
      .catch((err) => { setError(message(err)); setBoot("login"); });
  }, []);

  if (boot === "loading") return <Splash />;
  if (boot === "setup") return <Setup onReady={async (password) => {
    const session = await post<{ csrf_token: string }>("/login", { password });
    setCSRF(session.csrf_token); setBoot("ready"); await loadAll();
  }} />;
  if (boot === "login") return <Login onReady={async (token) => {
    setCSRF(token); setBoot("ready"); await loadAll();
  }} />;

  const onboarding = repos.length === 0 || jobs.length === 0;
  return (
    <div class="app-shell">
      <Sidebar view={view} onView={setView} failures={overview?.failures || 0} />
      <main>
        <header class="topbar">
          <div>
            <span class="eyebrow">LOCAL BACKUP CONTROL</span>
            <h1>{labels[view]}</h1>
          </div>
          <div class="top-actions">
            <span class={`health ${overview?.failures ? "warn" : ""}`}><i />{overview?.failures ? `${overview.failures} 项需处理` : "运行正常"}</span>
            <button class="icon-button" title="刷新" onClick={loadAll}>↻</button>
          </div>
        </header>
        {error && <div class="alert"><span>{error}</span><button onClick={() => setError("")}>×</button></div>}
        {onboarding ? <Onboarding repos={repos} jobs={jobs} refresh={loadAll} onError={setError} /> :
          view === "overview" ? <Dashboard overview={overview} repositories={repos} jobs={jobs} runs={runs} onView={setView} /> :
          view === "jobs" ? <Jobs jobs={jobs} repos={repos} refresh={loadAll} onError={setError} /> :
          view === "runs" ? <Runs runs={runs} jobs={jobs} refresh={loadAll} onError={setError} /> :
          view === "snapshots" ? <Snapshots jobs={jobs} onError={setError} /> :
          <Settings repos={repos} refresh={loadAll} onError={setError} />}
      </main>
    </div>
  );
}

function Splash() {
  return <div class="auth-page"><div class="brand-lockup"><Logo /><p>正在检查本机服务…</p></div></div>;
}

function Setup({ onReady }: { onReady: (password: string) => Promise<void> }) {
  const [token, setToken] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState("");
  return <div class="auth-page">
    <section class="auth-card wide">
      <Logo />
      <StepRail current={1} />
      <div class="auth-copy"><span class="eyebrow">STEP 1 OF 4</span><h1>保护你的备份面板</h1><p>输入服务首次启动时输出的一次性令牌，并创建管理员密码。</p></div>
      <form onSubmit={async (event) => { event.preventDefault(); setError(""); if (password !== confirm) { setError("两次密码不一致"); return; } try { await post("/setup", { token, password }); await onReady(password); } catch (err) { setError(message(err)); } }}>
        <label>一次性 Setup Token<input value={token} onInput={(e) => setToken(e.currentTarget.value)} autocomplete="one-time-code" required /></label>
        <div class="form-grid"><label>管理员密码<input type="password" value={password} onInput={(e) => setPassword(e.currentTarget.value)} minlength={10} required /></label><label>确认密码<input type="password" value={confirm} onInput={(e) => setConfirm(e.currentTarget.value)} minlength={10} required /></label></div>
        {error && <p class="form-error">{error}</p>}
        <button class="primary" type="submit">继续配置 <span>→</span></button>
      </form>
    </section>
  </div>;
}

function Login({ onReady }: { onReady: (csrf: string) => Promise<void> }) {
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  return <div class="auth-page"><section class="auth-card">
    <Logo /><div class="auth-copy"><span class="eyebrow">WELCOME BACK</span><h1>进入 vback</h1><p>你的凭证和备份数据始终保留在这台机器上。</p></div>
    <form onSubmit={async (event) => { event.preventDefault(); try { const result = await post<{ csrf_token: string }>("/login", { password }); await onReady(result.csrf_token); } catch (err) { setError(message(err)); } }}>
      <label>管理员密码<input type="password" value={password} onInput={(e) => setPassword(e.currentTarget.value)} autofocus required /></label>
      {error && <p class="form-error">{error}</p>}<button class="primary" type="submit">登录 <span>→</span></button>
    </form>
  </section></div>;
}

function Sidebar({ view, onView, failures }: { view: View; onView: (v: View) => void; failures: number }) {
  const items: [View, string, string][] = [["overview", "概览", "⌂"], ["jobs", "备份任务", "◇"], ["runs", "运行记录", "↗"], ["snapshots", "快照恢复", "◫"], ["settings", "存储设置", "⚙"]];
  return <aside><Logo compact /><nav>{items.map(([id, label, icon]) =>
    <button class={view === id ? "active" : ""} onClick={() => onView(id)}><span>{icon}</span>{label}{id === "runs" && failures > 0 && <b>{failures}</b>}</button>
  )}</nav><div class="aside-foot"><span class="version">v2.0</span><p>单机 · 加密 · 增量</p></div></aside>;
}

function Logo({ compact = false }: { compact?: boolean }) {
  return <div class={`logo ${compact ? "compact" : ""}`}><div class="logo-mark">V</div><div><strong>vback</strong>{!compact && <small>Backup, without the noise.</small>}</div></div>;
}

function StepRail({ current }: { current: number }) {
  return <div class="step-rail">{["账户", "仓库", "任务", "就绪"].map((label, index) => <div class={index + 1 <= current ? "done" : ""}><span>{index + 1}</span><em>{label}</em></div>)}</div>;
}

function Onboarding({ repos, jobs, refresh, onError }: { repos: Repository[]; jobs: Job[]; refresh: () => Promise<void>; onError: (v: string) => void }) {
  const step = repos.length === 0 ? 2 : jobs.length === 0 ? 3 : 4;
  return <section class="onboarding panel">
    <StepRail current={step} />
    {step === 2 ? <><span class="eyebrow">STEP 2 OF 4</span><h2>连接加密备份仓库</h2><p>凭证单独保存在权限为 0600 的本机文件中，不会返回到浏览器。</p><RepositoryForm onSaved={refresh} onError={onError} /></> :
      <><span class="eyebrow">STEP 3 OF 4</span><h2>创建第一个备份任务</h2><p>先从一个关键目录开始。第二次运行只会上传变化的数据。</p><JobForm repositories={repos} onSaved={refresh} onError={onError} /></>}
  </section>;
}

function Dashboard({ overview, repositories, jobs, runs, onView }: { overview: Overview | null; repositories: Repository[]; jobs: Job[]; runs: Run[]; onView: (v: View) => void }) {
  const latest = runs[0];
  const unhealthy = repositories.filter(repository => repository.health === "error").length;
  return <div class="stack">
    <section class="hero-grid">
      <article class="hero-card">
        <div><span class="eyebrow">LAST BACKUP</span><Status status={latest?.status || "idle"} /><h2>{latest ? runTitle(latest, jobs) : "尚未运行备份"}</h2><p>{latest ? formatDate(latest.started_at) : "运行一次备份后，这里会显示完整状态。"}</p></div>
        <button class="text-button" onClick={() => onView("runs")}>查看运行详情 →</button>
      </article>
      <article class="metric accent"><span>活跃任务</span><strong>{overview?.jobs || 0}</strong><small>{overview?.running ? `${overview.running} 个正在运行` : "当前没有排队任务"}</small></article>
      <article class="metric"><span>近 7 日失败</span><strong>{overview?.failures || 0}</strong><small>{overview?.failures ? "建议检查运行日志" : "保持得很好"}</small></article>
      <article class="metric"><span>已创建快照</span><strong>{overview?.snapshots || 0}</strong><small>{latest?.data_added ? `最近新增 ${formatBytes(latest.data_added)}` : "等待首次增量统计"}</small></article>
      <article class="metric"><span>仓库健康</span><strong>{unhealthy ? `${unhealthy} 异常` : "正常"}</strong><small>{repositories.length} 个加密仓库</small></article>
    </section>
    <section class="content-grid">
      <article class="panel">
        <div class="panel-head"><div><span class="eyebrow">7 DAY ACTIVITY</span><h3>备份活动</h3></div></div>
        <Activity data={overview?.seven_days || {}} />
      </article>
      <article class="panel">
        <div class="panel-head"><div><span class="eyebrow">UP NEXT</span><h3>下次计划</h3></div><button class="text-button" onClick={() => onView("jobs")}>管理</button></div>
        <div class="schedule-list">{(overview?.next_jobs || []).slice(0, 4).map(job => <div><i /><span><strong>{job.name}</strong><small>{job.schedule} · {job.timezone}</small></span><time>{job.next_run_at ? relative(job.next_run_at) : "未计划"}</time></div>)}{!(overview?.next_jobs || []).length && <Empty text="没有启用的计划任务" />}</div>
      </article>
    </section>
    <RunTable runs={runs.slice(0, 6)} jobs={jobs} />
  </div>;
}

function Jobs({ jobs, repos, refresh, onError }: { jobs: Job[]; repos: Repository[]; refresh: () => Promise<void>; onError: (v: string) => void }) {
  const [editing, setEditing] = useState<Job | null>(null);
  return <div class="stack">
    <div class="section-actions"><p>{jobs.length} 个任务，默认每个仓库同时只执行一个写操作。</p><button class="primary small" onClick={() => setEditing(blankJob(repos[0]?.id))}>＋ 新建任务</button></div>
    {editing && <section class="panel"><div class="panel-head"><h3>{editing.id ? "编辑任务" : "新建任务"}</h3><button class="icon-button" onClick={() => setEditing(null)}>×</button></div><JobForm repositories={repos} job={editing} onSaved={async () => { setEditing(null); await refresh(); }} onError={onError} /></section>}
    <div class="card-list">{jobs.map(job => <article class="job-card"><div class="job-main"><Status status={job.enabled ? "success" : "idle"} /><div><h3>{job.name}</h3><p>{job.sources.map(s => s.path).join(" · ")}</p></div></div><div class="job-meta"><span>{job.schedule || "手动运行"}</span><span>保留 {job.retention.last} 份</span><span>{job.low_resource ? "低资源" : "标准"}</span></div><div class="job-actions"><button onClick={async () => { try { await post(`/jobs/${job.id}/run`); await refresh(); } catch (e) { onError(message(e)); } }}>立即备份</button><button onClick={() => setEditing(job)}>编辑</button></div></article>)}</div>
  </div>;
}

function Runs({ runs, jobs, refresh, onError }: { runs: Run[]; jobs: Job[]; refresh: () => Promise<void>; onError: (v: string) => void }) {
  const active = runs.find(r => ["running", "queued"].includes(r.status));
  useRunEvents(active?.id, refresh);
  return <div class="stack">{active && <article class="live-card"><div><span class="live-dot" /><span class="eyebrow">LIVE RUN</span><h2>{runTitle(active, jobs)}</h2></div><Progress run={active} /><button onClick={async () => { try { await post(`/runs/${active.id}/cancel`); } catch (e) { onError(message(e)); } }}>取消</button></article>}<RunTable runs={runs} jobs={jobs} onRetry={async run => { try { await post(`/runs/${run.id}/retry`); await refresh(); } catch (e) { onError(message(e)); } }} /></div>;
}

function Snapshots({ jobs, onError }: { jobs: Job[]; onError: (v: string) => void }) {
  const [jobID, setJobID] = useState(jobs[0]?.id || "");
  const [items, setItems] = useState<Snapshot[]>([]);
  const [selected, setSelected] = useState("");
  const [files, setFiles] = useState<Array<{ path: string; name: string; type: string; size: number }>>([]);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const visibleFiles = useMemo(() => files.filter(file => file.path.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())), [files, query]);
  async function load() { setLoading(true); try { setItems(await api<Snapshot[]>(`/snapshots?job_id=${encodeURIComponent(jobID)}`) || []); } catch (e) { onError(message(e)); } finally { setLoading(false); } }
  useEffect(() => { if (jobID) load(); }, [jobID]);
  async function browse(snapshotID: string) {
    try {
      const result = await api<typeof files>(`/snapshots/tree?job_id=${encodeURIComponent(jobID)}&snapshot_id=${encodeURIComponent(snapshotID)}`);
      setSelected(snapshotID); setFiles((result || []).slice(0, 500));
    } catch (e) { onError(message(e)); }
  }
  return <div class="stack"><div class="section-actions"><label class="inline-label">任务<select value={jobID} onChange={e => setJobID(e.currentTarget.value)}>{jobs.map(job => <option value={job.id}>{job.name}</option>)}</select></label><button onClick={load}>刷新快照</button></div><div class="card-list">{items.map(snapshot => <article class="snapshot-wrap"><div class="snapshot-card"><div class="snapshot-icon">◫</div><div><Status status="success" /><h3>{snapshot.short_id || snapshot.id.slice(0, 8)}</h3><p>{formatDate(snapshot.time)} · {snapshot.hostname}</p><small>{snapshot.paths.join(" · ")}</small></div><div class="job-actions"><button onClick={() => browse(snapshot.id)}>浏览</button><button onClick={async () => { if (!confirm("恢复到受控 staging 目录？")) return; try { await post("/restore", { job_id: jobID, snapshot_id: snapshot.id, path: "" }); alert("恢复任务已创建，可在运行记录中查看。"); } catch (e) { onError(message(e)); } }}>安全恢复</button></div></div>{selected === snapshot.id && <div class="file-browser"><label>在已加载的文件中搜索<input type="search" value={query} onInput={e => setQuery(e.currentTarget.value)} placeholder="输入文件名或路径" /></label><div class="file-list">{visibleFiles.map(file => <div><span>{file.type === "dir" ? "◇" : "·"}</span><code title={file.path}>{file.path}</code><small>{file.type === "file" ? formatBytes(file.size) : "目录"}</small>{file.type === "file" && <a href={`/api/v1/snapshots/download?job_id=${encodeURIComponent(jobID)}&snapshot_id=${encodeURIComponent(snapshot.id)}&path=${encodeURIComponent(file.path)}`}>下载</a>}</div>)}{!visibleFiles.length && <Empty text={query ? "没有匹配的文件" : "快照中没有可显示的节点"} />}</div></div>}</article>)}{!loading && !items.length && <Empty text="这个任务还没有快照" />}{loading && <Empty text="正在读取加密仓库…" />}</div></div>;
}

function Settings({ repos, refresh, onError }: { repos: Repository[]; refresh: () => Promise<void>; onError: (v: string) => void }) {
  const [showForm, setShowForm] = useState(false);
  const [webhook, setWebhook] = useState("");
  const [monthlyFullCheck, setMonthlyFullCheck] = useState(false);
  const [pruneSchedule, setPruneSchedule] = useState("");
  useEffect(() => { api<{ webhook_url: string; monthly_full_check: boolean; prune_schedule: string }>("/settings").then(value => { setWebhook(value.webhook_url || ""); setMonthlyFullCheck(value.monthly_full_check); setPruneSchedule(value.prune_schedule || ""); }).catch(() => {}); }, []);
  return <div class="stack"><div class="section-actions"><p>凭证只保存在本机 secret 文件中。元数据检查固定每周日 UTC 04:00 执行。</p><button class="primary small" onClick={() => setShowForm(!showForm)}>＋ 添加仓库</button></div>{showForm && <section class="panel"><RepositoryForm onSaved={async () => { setShowForm(false); await refresh(); }} onError={onError} /></section>}<div class="card-list">{repos.map(repo => <article class="repo-card"><div><Status status={repo.health === "healthy" ? "success" : repo.health === "error" ? "failed" : "idle"} /><h3>{repo.name}</h3><p>{repo.provider || "Custom S3"} · {repo.bucket}/{repo.prefix}</p><small>{repo.endpoint}</small></div><div class="job-actions"><button onClick={async () => { if (!confirm("Prune 会锁定仓库且可能耗时较长，确定继续？")) return; try { await post("/maintenance", { repository_id: repo.id, action: "prune" }); await refresh(); } catch (e) { onError(message(e)); } }}>清理数据</button><button onClick={async () => { try { await post(`/repositories/${repo.id}/check`); await refresh(); } catch (e) { onError(message(e)); } }}>检查仓库</button><button onClick={async () => { if (!confirm("完整数据检查会读取全部数据，确定继续？")) return; try { await post("/maintenance", { repository_id: repo.id, action: "full-check" }); await refresh(); } catch (e) { onError(message(e)); } }}>完整检查</button></div></article>)}</div><section class="panel"><div class="panel-head"><div><span class="eyebrow">MAINTENANCE & ALERTS</span><h3>维护与失败告警</h3></div></div><form class="form-stack" onSubmit={async e => { e.preventDefault(); try { await post("/settings", { webhook_url: webhook, monthly_full_check: monthlyFullCheck, prune_schedule: pruneSchedule }); alert("维护与告警设置已保存"); } catch (err) { onError(message(err)); } }}><label>HTTPS Webhook URL<input type="url" value={webhook} onInput={e => setWebhook(e.currentTarget.value)} placeholder="https://example.com/vback-alert" /></label><label>Prune 五字段 Cron（留空为仅手动）<input value={pruneSchedule} onInput={e => setPruneSchedule(e.currentTarget.value)} placeholder="0 5 * * 0" /></label><div class="toggle-row"><label><input type="checkbox" checked={monthlyFullCheck} onChange={e => setMonthlyFullCheck(e.currentTarget.checked)} />每月 1 日 UTC 05:00 完整数据检查</label></div><button class="primary small" type="submit">保存维护设置</button></form></section></div>;
}

function RepositoryForm({ onSaved, onError }: { onSaved: () => Promise<void>; onError: (v: string) => void }) {
  const [value, setValue] = useState({ name: "", provider: "custom", endpoint: "", bucket: "", prefix: "vback-v2", region: "us-east-1", access_key: "", secret_key: "", restic_password: "" });
  const presets: Record<string, Partial<typeof value>> = { bitiful: { endpoint: "s3.bitiful.net", region: "cn-east-1" }, aws: { endpoint: "s3.us-east-1.amazonaws.com", region: "us-east-1" }, cloudflare: { endpoint: "", region: "auto" }, aliyun: { endpoint: "oss-cn-hangzhou.aliyuncs.com", region: "cn-hangzhou" }, qiniu: { endpoint: "s3-cn-east-1.qiniucs.com", region: "cn-east-1" }, gcloud: { endpoint: "storage.googleapis.com", region: "us" }, custom: { endpoint: "", region: "us-east-1" } };
  return <form class="form-stack" onSubmit={async (e) => { e.preventDefault(); try { const repo = await post<Repository>("/repositories", value); await post(`/repositories/${repo.id}/init`); await onSaved(); } catch (err) { onError(message(err)); } }}>
    <div class="form-grid three"><label>名称<input value={value.name} onInput={e => setValue({ ...value, name: e.currentTarget.value })} placeholder="Primary S3" required /></label><label>提供商<select value={value.provider} onChange={e => { const provider = e.currentTarget.value; setValue({ ...value, provider, ...presets[provider] }); }}><option value="custom">Custom S3</option><option value="bitiful">缤纷云 S4</option><option value="aws">AWS S3</option><option value="cloudflare">Cloudflare R2</option><option value="aliyun">Aliyun OSS</option><option value="qiniu">七牛云</option><option value="gcloud">Google Cloud</option></select></label><label>Region<input value={value.region} onInput={e => setValue({ ...value, region: e.currentTarget.value })} /></label></div>
    <div class="form-grid"><label>Endpoint<input value={value.endpoint} onInput={e => setValue({ ...value, endpoint: e.currentTarget.value })} placeholder="s3.example.com" required /></label><label>Bucket<input value={value.bucket} onInput={e => setValue({ ...value, bucket: e.currentTarget.value })} required /></label></div>
    <label>v2 仓库前缀<input value={value.prefix} onInput={e => setValue({ ...value, prefix: e.currentTarget.value })} /></label>
    <div class="form-grid"><label>Access Key<input value={value.access_key} onInput={e => setValue({ ...value, access_key: e.currentTarget.value })} autocomplete="off" required /></label><label>Secret Key<input type="password" value={value.secret_key} onInput={e => setValue({ ...value, secret_key: e.currentTarget.value })} autocomplete="new-password" required /></label></div>
    <label>Restic 恢复密钥<input type="password" value={value.restic_password} onInput={e => setValue({ ...value, restic_password: e.currentTarget.value })} minlength={12} required /><small>请离线保存。丢失后无法恢复加密快照。</small></label>
    <button class="primary" type="submit">保存仓库 <span>→</span></button>
  </form>;
}

function JobForm({ repositories, job, onSaved, onError }: { repositories: Repository[]; job?: Job; onSaved: () => Promise<void>; onError: (v: string) => void }) {
  const [value, setValue] = useState(job || blankJob(repositories[0]?.id));
  const sourceText = value.sources.map(s => s.path).join("\n");
  const excludeText = value.excludes.join("\n");
  const sqliteText = value.sqlite_sources.map(s => s.path).join("\n");
  return <form class="form-stack" onSubmit={async e => { e.preventDefault(); try { await post("/jobs", value); await onSaved(); } catch (err) { onError(message(err)); } }}>
    <div class="form-grid"><label>任务名称<input value={value.name} onInput={e => setValue({ ...value, name: e.currentTarget.value })} required /></label><label>备份仓库<select value={value.repository_id} onChange={e => setValue({ ...value, repository_id: e.currentTarget.value })}>{repositories.map(repo => <option value={repo.id}>{repo.name}</option>)}</select></label></div>
    <label>来源目录（每行一个绝对路径）<textarea value={sourceText} onInput={e => setValue({ ...value, sources: e.currentTarget.value.split("\n").filter(Boolean).map(path => ({ path: path.trim(), alias: path.trim().split("/").pop() || "root" })) })} placeholder={"/var/www\n/etc/nginx"} required /></label>
    <label>排除规则（每行一个）<textarea value={excludeText} onInput={e => setValue({ ...value, excludes: e.currentTarget.value.split("\n").filter(Boolean) })} placeholder={"*.log\nnode_modules\n.cache"} /></label>
    <label>SQLite 一致性来源（可选，每行一个数据库绝对路径）<textarea value={sqliteText} onInput={e => setValue({ ...value, sqlite_sources: e.currentTarget.value.split("\n").filter(Boolean).map(path => ({ path: path.trim(), alias: path.trim().split("/").pop() || "database.sqlite" })) })} placeholder="/var/lib/app/data.sqlite" /></label>
    <div class="form-grid three"><label>Cron<input value={value.schedule} onInput={e => setValue({ ...value, schedule: e.currentTarget.value })} placeholder="0 3 * * *" /></label><label>时区<input value={value.timezone} onInput={e => setValue({ ...value, timezone: e.currentTarget.value })} /></label><label>带宽限制 KB/s<input type="number" min="0" value={value.bandwidth_kb} onInput={e => setValue({ ...value, bandwidth_kb: Number(e.currentTarget.value) })} /></label></div>
    <div class="form-grid retention-grid"><label>保留最近<input type="number" min="0" value={value.retention.last} onInput={e => setValue({ ...value, retention: { ...value.retention, last: Number(e.currentTarget.value) } })} /></label><label>每小时<input type="number" min="0" value={value.retention.hourly} onInput={e => setValue({ ...value, retention: { ...value.retention, hourly: Number(e.currentTarget.value) } })} /></label><label>每日<input type="number" min="0" value={value.retention.daily} onInput={e => setValue({ ...value, retention: { ...value.retention, daily: Number(e.currentTarget.value) } })} /></label><label>每周<input type="number" min="0" value={value.retention.weekly} onInput={e => setValue({ ...value, retention: { ...value.retention, weekly: Number(e.currentTarget.value) } })} /></label><label>每月<input type="number" min="0" value={value.retention.monthly} onInput={e => setValue({ ...value, retention: { ...value.retention, monthly: Number(e.currentTarget.value) } })} /></label></div>
    <div class="toggle-row"><label><input type="checkbox" checked={value.enabled} onChange={e => setValue({ ...value, enabled: e.currentTarget.checked })} />启用计划</label><label><input type="checkbox" checked={value.low_resource} onChange={e => setValue({ ...value, low_resource: e.currentTarget.checked })} />低资源模式</label><label><input type="checkbox" checked={value.one_file_system} onChange={e => setValue({ ...value, one_file_system: e.currentTarget.checked })} />不跨文件系统</label></div>
    <button class="primary" type="submit">保存任务 <span>→</span></button>
  </form>;
}

function RunTable({ runs, jobs, onRetry }: { runs: Run[]; jobs: Job[]; onRetry?: (run: Run) => Promise<void> }) {
  return <section class="panel table-panel"><div class="panel-head"><div><span class="eyebrow">RUN HISTORY</span><h3>最近运行</h3></div></div><div class="run-table"><div class="table-head"><span>任务</span><span>状态</span><span>处理数据</span><span>开始时间</span></div>{runs.map(run => <div class="table-row"><span><strong>{runTitle(run, jobs)}</strong><small>{run.kind}{run.dry_run ? " · dry-run" : ""}</small></span><Status status={run.status} /><span>{formatBytes(run.data_added || run.bytes_done)}</span><time>{relative(run.started_at)}</time>{run.error && <p class="row-error">{run.error}</p>}{onRetry && run.kind === "backup" && ["failed", "partial", "cancelled"].includes(run.status) && <button class="text-button retry-button" onClick={() => onRetry(run)}>重试</button>}</div>)}{!runs.length && <Empty text="还没有运行记录" />}</div></section>;
}

function Activity({ data }: { data: Record<string, number> }) {
  const days = Array.from({ length: 7 }, (_, offset) => { const d = new Date(); d.setDate(d.getDate() - (6 - offset)); const key = d.toISOString().slice(0, 10); return { key, value: data[key] || 0, label: `${d.getMonth() + 1}/${d.getDate()}` }; });
  const max = Math.max(1, ...days.map(d => d.value));
  return <div class="activity">{days.map(day => <div><div class="bar-track"><i style={{ height: `${Math.max(7, day.value / max * 100)}%` }}><b>{day.value}</b></i></div><span>{day.label}</span></div>)}</div>;
}

function Progress({ run }: { run: Run }) {
  const value = run.bytes_total ? Math.round(run.bytes_done / run.bytes_total * 100) : 0;
  return <div class="progress-wrap"><div><span>{value}%</span><small>{formatBytes(run.bytes_done)} / {formatBytes(run.bytes_total)}</small></div><div class="progress"><i style={{ width: `${value}%` }} /></div></div>;
}

function Status({ status }: { status: string }) {
  const map: Record<string, string> = { success: "成功", running: "运行中", queued: "排队", failed: "失败", partial: "不完整", cancelled: "已取消", idle: "未检查" };
  return <span class={`status ${status}`}><i />{map[status] || status}</span>;
}

function Empty({ text }: { text: string }) { return <div class="empty"><span>◇</span><p>{text}</p></div>; }

function useRunEvents(runID: string | undefined, refresh: () => Promise<void>) {
  useEffect(() => {
    if (!runID) return;
    const source = new EventSource(`/api/v1/runs/${runID}/events`);
    let timer = 0;
    const onEvent = () => { window.clearTimeout(timer); timer = window.setTimeout(refresh, 200); };
    source.onmessage = onEvent;
    ["progress", "summary", "success", "failed", "partial", "cancelled"].forEach(type => source.addEventListener(type, onEvent));
    return () => { window.clearTimeout(timer); source.close(); };
  }, [runID]);
}

function blankJob(repositoryID = ""): Job {
  return { id: "", name: "", repository_id: repositoryID, sources: [], sqlite_sources: [], excludes: ["*.log", "*.tmp", "node_modules", ".git"], schedule: "0 3 * * *", timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC", retention: emptyRetention, bandwidth_kb: 0, one_file_system: false, low_resource: true, enabled: true };
}

const labels: Record<View, string> = { overview: "备份概览", jobs: "备份任务", runs: "运行记录", snapshots: "快照与恢复", settings: "存储仓库" };
const message = (error: unknown) => error instanceof Error ? error.message : String(error);
const runTitle = (run: Run, jobs: Job[]) => jobs.find(job => job.id === run.job_id)?.name || (run.kind === "check" ? "仓库检查" : "未知任务");
const formatDate = (value: string) => new Intl.DateTimeFormat("zh-CN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
const relative = (value: string) => { const seconds = Math.round((new Date(value).getTime() - Date.now()) / 1000); const formatter = new Intl.RelativeTimeFormat("zh-CN", { numeric: "auto" }); if (Math.abs(seconds) < 60) return formatter.format(seconds, "second"); const minutes = Math.round(seconds / 60); if (Math.abs(minutes) < 60) return formatter.format(minutes, "minute"); const hours = Math.round(minutes / 60); if (Math.abs(hours) < 48) return formatter.format(hours, "hour"); return formatter.format(Math.round(hours / 24), "day"); };
const formatBytes = (bytes: number) => { if (!bytes) return "0 B"; const units = ["B", "KB", "MB", "GB", "TB"]; const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1); return `${(bytes / 1024 ** index).toFixed(index ? 1 : 0)} ${units[index]}`; };

render(<App />, document.getElementById("app")!);
