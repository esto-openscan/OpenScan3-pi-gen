<?php
declare(strict_types=1);
@set_time_limit(1800);

function h($s) { return htmlspecialchars((string)$s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }

$action = $_GET['action'] ?? ($_POST['action'] ?? '');

if ($action === 'download_settings') {
    header('Content-Type: application/gzip');
    header('Content-Disposition: attachment; filename="openscan3-settings.tar.gz"');
    $cmd = 'tar -C /etc/openscan3 -cz .';
    passthru($cmd, $code);
    exit;
}

if ($action === 'download_flows') {
    $flows = '/opt/openscan3/.node-red/flows.json';
    if (!is_readable($flows)) {
        http_response_code(404);
        echo 'flows.json not found';
        exit;
    }
    header('Content-Type: application/json');
    header('Content-Disposition: attachment; filename="flows.json"');
    readfile($flows);
    exit;
}

$updateOutput = '';
if ($action === 'update' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    $branch = trim((string)($_POST['branch'] ?? 'develop'));
    if ($branch === '') { $branch = 'develop'; }
    $keepSettings = isset($_POST['keep_settings']);
    $keepFlows = isset($_POST['keep_flows']);

    $cmd = '/usr/bin/sudo /usr/local/sbin/openscan3-update';
    $args = [];
    if ($branch !== '') { $args[] = '--branch ' . escapeshellarg($branch); }
    if ($keepSettings) { $args[] = '--keep-settings'; }
    if ($keepFlows) { $args[] = '--keep-flows'; }
    $cmdline = $cmd . ' ' . implode(' ', $args) . ' 2>&1';
    $updateOutput = shell_exec($cmdline) ?? '';
}

$hostname = trim(shell_exec('hostname 2>/dev/null') ?? '');
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OpenScan Admin</title>
  <style>
    body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, 'Helvetica Neue', Arial, 'Noto Sans', 'Liberation Sans', sans-serif; margin: 2rem; color: #222; }
    .container { max-width: 900px; margin: 0 auto; }
    h1 { margin-bottom: .5rem; }
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 1rem; }
    .card { border: 1px solid #ddd; border-radius: 8px; padding: 1rem; background: #fafafa; }
    .btn { display: inline-block; padding: .6rem 1rem; border-radius: 6px; border: 1px solid #888; background: #fff; text-decoration: none; color: #111; }
    .btn.primary { background: #007acc; color: #fff; border-color: #007acc; }
    .muted { color: #666; }
    .warning { border-left: 4px solid #c62828; background: #fff3f0; color: #8b1a1a; padding: .75rem 1rem; border-radius: 4px; font-weight: 600; }
    form .row { margin: .5rem 0; }
    label { display:block; font-weight:600; margin-bottom: .25rem; }
    input[type=text] { width: 100%; padding: .5rem; border:1px solid #ccc; border-radius: 4px; }
    .output { white-space: pre-wrap; background: #111; color: #eee; padding: 1rem; border-radius: 6px; overflow-x:auto; max-height: 50vh; }
  </style>
</head>
<body>
<div class="container">
  <h1>OpenScan Admin</h1>
  <p class="muted">Host: <?= h($hostname) ?> · This page lets you export settings/flows and trigger an update.</p>

  <div class="cards">
    <div class="card">
      <h3>Export</h3>
      <p>Download current configuration and flows for debugging/backups.</p>
      <p>
        <a class="btn" href="?action=download_settings">Download settings (tar.gz)</a>
      </p>
      <p>
        <a class="btn" href="?action=download_flows">Download flows.json</a>
      </p>
    </div>

    <div class="card">
      <h3>Update (Quick & Dirty)</h3>
      <form method="post">
        <input type="hidden" name="action" value="update">
        <div class="row">
          <label for="branch">Branch</label>
          <input id="branch" name="branch" type="text" value="<?= h($_POST['branch'] ?? 'develop') ?>">
        </div>
        <div class="row">
          <div class="warning">Keeping settings or flows can leave stale data behind and trigger hard-to-debug issues. Leave both unchecked unless you know what you're doing.</div>
        </div>
        <div class="row">
          <label><input type="checkbox" name="keep_settings" <?= isset($_POST['keep_settings']) ? 'checked' : '' ?>> Keep settings (/etc/openscan3)</label>
        </div>
        <div class="row">
          <label><input type="checkbox" name="keep_flows" <?= isset($_POST['keep_flows']) ? 'checked' : '' ?>> Keep flows (/opt/openscan3/.node-red/flows.json)</label>
        </div>
        <div class="row">
          <button class="btn primary" type="submit">Run Update</button>
        </div>
        <p class="muted">This will stop services, force pull the source repo, sync runtime, rebuild venv, reset settings/flows (unless kept), and restart services.</p>
      </form>
    </div>
  </div>

  <?php if ($updateOutput !== ''): ?>
    <h3>Update Output</h3>
    <div class="output"><?= h($updateOutput) ?></div>
  <?php endif; ?>
</div>
</body>
</html>
