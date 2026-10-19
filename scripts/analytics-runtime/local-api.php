<?php
/** API local administrativa. Entrada JSON no stdin; nunca aceita acesso via HTTP. */
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { exit(1); }
define('PIWIK_DOCUMENT_ROOT', '/var/www/html');
define('PIWIK_INCLUDE_PATH', PIWIK_DOCUMENT_ROOT);
require PIWIK_INCLUDE_PATH . '/core/bootstrap.php';
(new Piwik\Application\Environment('cli'))->init();
Piwik\Console::initPlugins();
$parameters = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
// Não ofereça pela rede: o processo precisa de permissão de docker/root no servidor.
Piwik\Access::doAsSuperUser(function () use ($parameters) {
    $parameters['format'] = 'JSON';
    $result = (new Piwik\API\Request($parameters))->process();
    echo $result . "\n";
});
