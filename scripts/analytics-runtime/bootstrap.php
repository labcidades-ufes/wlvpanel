<?php
/** Instalação local única usando as mesmas APIs do instalador oficial, sem email. */
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { exit(1); }
define('PIWIK_DOCUMENT_ROOT', '/var/www/html');
define('PIWIK_INCLUDE_PATH', PIWIK_DOCUMENT_ROOT);
require PIWIK_INCLUDE_PATH . '/core/bootstrap.php';
$secret = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
$configFile = PIWIK_DOCUMENT_ROOT . '/config/config.ini.php';
$resume = in_array('--resume', $argv, true);
if (file_exists($configFile) && !$resume) { throw new RuntimeException('Configuração existente: não sobrescrita.'); }
$db = $secret['db_password'];
if (!preg_match('/^[a-f0-9]{64}$/', $db)) { throw new RuntimeException('Segredo inválido.'); }
$salt = bin2hex(random_bytes(32));
$ini = "; <?php exit; ?> DO NOT REMOVE THIS LINE\n[database]\nhost = db\nusername = matomo\npassword = $db\ndbname = matomo\ntables_prefix = matomo_\nadapter = PDO\\MYSQL\ncharset = utf8mb4\ncollation = utf8mb4_unicode_ci\n\n[General]\nsalt = $salt\ninstallation_in_progress = 1\ntrusted_hosts[] = worldlabourvalues.org\nassume_secure_protocol = 1\nforce_ssl = 1\nproxy_client_headers[] = HTTP_X_FORWARDED_FOR\nproxy_host_headers[] = HTTP_X_FORWARDED_HOST\nproxy_uri_header = 1\nemails_enabled = 0\nenable_update_users_email = 0\nenable_browser_archiving_triggering = 0\nbrowser_archiving_disabled_enforce = 1\n\n[Tracker]\nuse_third_party_id_cookie = 0\n";
if (!$resume) { file_put_contents($configFile, $ini, LOCK_EX); }
chmod($configFile, 0640);
$environment = new Piwik\Application\Environment('cli');
$environment->init();
Piwik\Console::initPlugins();
if ($resume && empty(Piwik\Config::getInstance()->General['installation_in_progress'])) { throw new RuntimeException('Retomada permitida só para instalação incompleta.'); }
Piwik\Access::doAsSuperUser(function () use ($secret) {
    if (count(Piwik\DbHelper::getTablesInstalled()) === 0) {
        Piwik\DbHelper::createTables();
        Piwik\DbHelper::createAnonymousUser();
        Piwik\DbHelper::recordInstallVersion();
    }
    $updater = new Piwik\Updater();
    $updates = $updater->getComponentUpdates();
    if ($updates) {
        $result = $updater->updateComponents($updates);
        if (!empty($result['coreError']) || !empty($result['errors'])) { throw new RuntimeException('Falha ao instalar componentes.'); }
    }
    Piwik\Updater::recordComponentSuccessfullyUpdated('core', Piwik\Version::VERSION);
    Piwik\Plugin\Manager::getInstance()->installLoadedPlugins();
    $admin = $secret['admin'];
    if (!Piwik\Plugins\UsersManager\API::getInstance()->userExists($admin['username'])) {
        Piwik\Plugins\UsersManager\API::getInstance()->addUser($admin['username'], $admin['password'], $admin['email']);
    }
    (new Piwik\Plugins\UsersManager\UserUpdater())->setSuperUserAccessWithoutCurrentPassword($admin['username'], true);
    $sites = Piwik\Plugins\SitesManager\API::getInstance();
    $existingIds = $sites->getAllSitesId();
    $production = in_array(1, $existingIds) ? 1 : $sites->addSite('World Labour Values', ['https://worldlabourvalues.org/', 'https://panel.worldlabourvalues.org/'], 0, 0, '', '', '', '', 'America/Sao_Paulo', 'BRL', 'WLV', null, '', 0, 'website', [], 1);
    $staging = in_array(2, $existingIds) ? 2 : $sites->addSite('World Labour Values — homologação', ['http://127.0.0.1:8094/', 'http://127.0.0.1:3840/', 'http://127.0.0.1:3839/', 'https://worldlabourvalues.org/'], 0, 0, '', '', '', '', 'America/Sao_Paulo', 'BRL', 'WLV', null, '', 0, 'website', [], 0);
    if ($production !== 1 || $staging !== 2) { throw new RuntimeException('IDs inesperados.'); }
    $privacy = new Piwik\Plugins\PrivacyManager\Config();
    $privacy->ipAnonymizerEnabled = true;
    $privacy->ipAddressMaskLength = 2;
    $privacy->useAnonymizedIpForVisitEnrichment = false;
    $privacy->doNotTrackEnabled = true;
    $privacy->forceCookielessTracking = true;
    $privacy->anonymizeReferrer = Piwik\Plugins\PrivacyManager\ReferrerAnonymizer::EXCLUDE_QUERY;
    Piwik\Plugins\PrivacyManager\PrivacyManager::savePurgeDataSettings([
        'delete_logs_enable' => 1, 'delete_logs_older_than' => 90,
        'delete_logs_schedule_lowest_interval' => 1, 'delete_reports_enable' => 0,
    ]);
    Piwik\Plugins\Installation\ServerFilesGenerator::createFilesForSecurity();
    $config = Piwik\Config::getInstance();
    unset($config->General['installation_in_progress'], $config->General['installation_first_accessed']);
    $config->forceSave();
    Piwik\Option::set('piwikUrl', 'https://worldlabourvalues.org/estatisticas/');
    Piwik\Tracker\Cache::deleteTrackerCache();
    echo json_encode(['version' => Piwik\Version::VERSION, 'production_site' => $production, 'staging_site' => $staging, 'email_enabled' => false, 'bootstrap_complete' => true], JSON_PRETTY_PRINT) . "\n";
});
