<?php

declare(strict_types=1);

$dsn = getenv('DB_DSN') ?: 'oci:dbname=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=127.0.0.1)(PORT=1521))(CONNECT_DATA=(SID=OD)))';
$username = getenv('DB_USER') ?: 'app_user';
$password = getenv('DB_PASSWORD') ?: '';

try {
    $pdo = new PDO($dsn, $username, $password, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);

    $rows = $pdo->query(
        'SELECT id, name, email
         FROM (SELECT id, name, email FROM users ORDER BY id)
         WHERE ROWNUM <= 10'
    )->fetchAll();

    echo json_encode($rows, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR) . PHP_EOL;
} catch (PDOException $exception) {
    fwrite(STDERR, "Database query failed: {$exception->getMessage()}" . PHP_EOL);
    exit(1);
}
