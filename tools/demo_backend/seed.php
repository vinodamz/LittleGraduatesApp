<?php
declare(strict_types=1);
$root = realpath($argv[1] ?? '') ?: '';
if ($root === '' || @file_get_contents($root . '/.demo-only') !== "LG_ANDROID_DEMO\n") throw new RuntimeException('Not a demo runtime');
$cfg = require $root . '/mtt/includes/config.php';
if (($cfg['demo_backend'] ?? false) !== true || $cfg['db']['name'] !== 'lg_android_demo' || $cfg['db']['host'] !== 'localhost;unix_socket=' . $root . '/db.sock') throw new RuntimeException('Refusing non-isolated database');
require $root . '/mtt/includes/db.php';
$db = db();
if ((int)$db->query('SELECT COUNT(*) FROM users')->fetchColumn() !== 0) throw new RuntimeException('Demo requires a fresh database without existing people');
$db->beginTransaction();
$db->exec('UPDATE staff_duty_templates SET is_active = 0');
$db->exec('UPDATE mm_materials SET is_active = 0');
$name = 'Demo Materials Teacher';
$pin = '654321';
$db->prepare("INSERT INTO users(name,pin_hash,role,modules,active) VALUES(?,?,'teacher','materials',1)")->execute([$name, password_hash($pin, PASSWORD_DEFAULT)]);
$userId = (int)$db->lastInsertId();
$materials = [];
foreach (['Demo Pink Tower', 'Demo Number Rods'] as $index => $label) {
    $db->prepare("INSERT INTO mm_materials(name,location,sort_order,is_active) VALUES(?,'Demo shelf',?,1)")->execute([$label, $index]);
    $materials[] = ['id' => (int)$db->lastInsertId(), 'name' => $label, 'location' => 'Demo shelf'];
}
$settings = ['app_name' => 'Little Graduates Demo', 'app_short_name' => 'LG Demo', 'site_base_url' => '', 'wacrm_url' => '', 'wacrm_sso_secret' => '', 'n8n_url' => ''];
$set = $db->prepare('INSERT INTO app_settings(setting_key,setting_value) VALUES(?,?) ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value)');
foreach ($settings as $key => $value) $set->execute([$key, $value]);
$db->commit();
$fixture = ['demo_only' => true, 'backend' => 'real MTT PHP API and MariaDB; synthetic records; router-delayed upload acknowledgement', 'mtt_commit' => trim((string)file_get_contents($root . '/mtt-commit.txt')), 'school' => 'Little Graduates Demo', 'user' => ['id' => $userId, 'name' => $name, 'pin' => $pin, 'role' => 'teacher'], 'materials' => $materials, 'media_file' => $root . '/demo-material.png'];
if (file_put_contents($root . '/fixture.json', json_encode($fixture, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n") === false) throw new RuntimeException('Cannot write fixture manifest');
echo "Seeded synthetic Materials teacher and two demo materials.\n";
