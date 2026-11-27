<?php
declare(strict_types=1);
$root = realpath($argv[1] ?? '') ?: '';
if ($root === '' || @file_get_contents($root . '/.demo-only') !== "LG_ANDROID_DEMO\n") throw new RuntimeException('Not a demo runtime');
$config = [
    'demo_backend' => true,
    'db' => ['host' => 'localhost;unix_socket=' . $root . '/db.sock', 'name' => 'lg_android_demo', 'user' => 'root', 'password' => '', 'charset' => 'utf8mb4'],
    'app' => ['name' => 'Little Graduates Demo', 'short_name' => 'LG Demo', 'session_name' => 'LG_ANDROID_DEMO', 'timezone' => 'Asia/Kolkata', 'max_pin_tries' => 5, 'lock_seconds' => 30],
];
$path = $root . '/mtt/includes/config.php';
if (file_exists($path)) throw new RuntimeException('Refusing to overwrite config');
if (file_put_contents($path, "<?php\nreturn " . var_export($config, true) . ";\n", LOCK_EX) === false) throw new RuntimeException('Cannot write demo config');
chmod($path, 0600);
