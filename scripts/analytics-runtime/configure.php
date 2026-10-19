<?php
/** Configuração pós-instalação, repetível sem substituir dimensões/painéis existentes. */
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { exit(1); }
define('PIWIK_DOCUMENT_ROOT', '/var/www/html');
define('PIWIK_INCLUDE_PATH', PIWIK_DOCUMENT_ROOT);
$_GET['idSite'] = $_REQUEST['idSite'] = 1;
require PIWIK_INCLUDE_PATH . '/core/bootstrap.php';
(new Piwik\Application\Environment('cli'))->init();
Piwik\Console::initPlugins();
require __DIR__ . '/dashboard-widgets.php';
Piwik\Access::doAsSuperUser(function () {
    $privacy = new Piwik\Plugins\PrivacyManager\Config();
    $privacy->anonymizeReferrer = Piwik\Plugins\PrivacyManager\ReferrerAnonymizer::EXCLUDE_QUERY;
    $config = Piwik\Config::getInstance();
    $config->General['piwik_professional_support_ads_enabled'] = 0;
    $config->forceSave();
    $tracking = new Piwik\Plugins\CustomDimensions\Dao\LogTable('action');
    $count = $tracking->getNumInstalledIndexes();
    if ($count < 10) { $tracking->addManyCustomDimensions(10 - $count); }
    $dimensions = ['kind' => 'Tipo de exportação', 'format' => 'Formato', 'method' => 'Base de dados',
        'country' => 'País selecionado', 'partner' => 'Parceiro selecionado', 'indicator' => 'Indicador',
        'years' => 'Período selecionado', 'sector' => 'Setor selecionado', 'release' => 'Versão dos dados',
        'filename' => 'Nome do arquivo'];
    $mapping = [];
    foreach ([1, 2] as $site) {
        $api = Piwik\Plugins\CustomDimensions\API::getInstance();
        $configured = $api->getConfiguredCustomDimensions($site);
        foreach (array_keys($dimensions) as $index => $key) {
            $expected = $index + 1;
            $found = array_values(array_filter($configured, fn($d) => (int)$d['idcustomdimension'] === $expected));
            if (!$found) {
                $actual = (int)$api->configureNewCustomDimension($site, $dimensions[$key], 'action', true, [], true, 'WLV: ' . $key);
                if ($actual !== $expected) { throw new RuntimeException('ID de dimensão inesperado.'); }
            } elseif ($found[0]['name'] !== $dimensions[$key] || $found[0]['scope'] !== 'action') {
                throw new RuntimeException('Dimensão existente incompatível: ' . $key);
            }
            $mapping[$site][$key] = $expected;
        }
    }
    Piwik\Plugins\LanguagesManager\API::getInstance()->setLanguageForUser('franklin', 'pt-br');
    Piwik\Plugins\GeoIp2\GeoIP2AutoUpdater::setUpdaterOptions([
        'loc' => 'https://download.db-ip.com/free/dbip-city-lite-' . date('Y-m') . '.mmdb.gz',
        'period' => 'month',
    ]);
    if (!glob(PIWIK_DOCUMENT_ROOT . '/misc/*[Cc]ity*.mmdb') && !glob(PIWIK_DOCUMENT_ROOT . '/misc/DBIP*.mmdb')) {
        Piwik\Plugins\GeoIp2\GeoIP2AutoUpdater::performUpdate();
    }
    Piwik\Plugins\UserCountry\LocationProvider::setCurrentProvider('geoip2php');
    $widget = 'wlvDashboardWidget';
    $model = new Piwik\Plugins\Dashboard\Model();
    if (!$model->getAllDashboardsForUser('franklin')) {
        $layout = [
            [$widget('VisitsSummary', 'get', ['viewDataTable' => 'sparklines']), $widget('VisitsSummary', 'getEvolutionGraph'), $widget('VisitTime', 'getVisitInformationPerLocalTime')],
            [$widget('UserCountry', 'getCountry'), $widget('UserCountry', 'getCity'), $widget('Referrers', 'getReferrerType'), $widget('Referrers', 'getWebsites')],
            [$widget('Actions', 'getPageTitles'), $widget('Events', 'getCategory'), $widget('CustomDimensions', 'getCustomDimension', ['idDimension' => 10]), $widget('Live', 'widget')],
        ];
        $model->createNewDashboardForUser('franklin', 'WLV — acessos, abas e exportações', json_encode($layout));
    }
    Piwik\Tracker\Cache::deleteTrackerCache();
    echo json_encode(['dimensions' => $mapping, 'geo_provider' => Piwik\Plugins\UserCountry\LocationProvider::getCurrentProviderId(), 'purge' => Piwik\Plugins\PrivacyManager\PrivacyManager::getPurgeDataSettings(), 'configured' => true], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . "\n";
});
