<?php
/** Local demo transport shim; all app API responses come from unmodified MTT. */
declare(strict_types=1);
$root = realpath((string)getenv('LG_DEMO_RUNTIME')) ?: '';
if ($root === '' || @file_get_contents($root . '/.demo-only') !== "LG_ANDROID_DEMO\n") {
    http_response_code(503); echo 'Demo runtime missing'; return true;
}
$path = parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH);
if ($path === '/demo/health') {
    header('Content-Type: application/json');
    echo json_encode(['demo_only' => true, 'backend' => 'MTT PHP + isolated MariaDB', 'mtt_commit' => trim((string)file_get_contents($root . '/mtt-commit.txt')), 'upload_delay_seconds' => (int)@file_get_contents($root . '/upload-delay-seconds')]);
    return true;
}
$allowed = ['/api/v1/login_users.php', '/api/v1/login.php', '/api/v1/me.php', '/api/v1/logout.php',
    '/api/v1/materials/today.php', '/api/v1/materials/mark.php', '/api/v1/materials/bulk_good.php', '/api/v1/materials/media.php', '/api/v1/materials/file.php'];
if (!is_string($path) || !in_array($path, $allowed, true)) {
    http_response_code(404); header('Content-Type: application/json');
    echo json_encode(['ok' => false, 'code' => 'demo_route_disabled', 'error' => 'This isolated demo serves only sign-in and materials.']);
    return true;
}
header('X-LG-Demo-Backend: real-mtt-synthetic-data');
$delay = $path === '/api/v1/materials/media.php' && ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST'
    ? max(0, min(120, (int)@file_get_contents($root . '/upload-delay-seconds'))) : 0;
$started = microtime(true);
register_shutdown_function(static function () use ($root, $path, $delay, $started): void {
    // No bodies, PINs, bearer tokens, query strings or filenames in this audit log.
    file_put_contents($root . '/requests.jsonl', json_encode(['path' => $path, 'method' => $_SERVER['REQUEST_METHOD'] ?? '', 'status' => http_response_code(), 'delay_seconds' => $delay, 'elapsed_seconds' => round(microtime(true) - $started, 3)]) . "\n", FILE_APPEND | LOCK_EX);
});
if ($delay > 0) sleep($delay);
require $root . '/mtt' . $path;
return true;
