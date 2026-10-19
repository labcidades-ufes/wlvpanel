<?php
/** Corrige somente IDs do dashboard WLV criado pela instalação inicial. */
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { exit(1); }
define('PIWIK_DOCUMENT_ROOT', '/var/www/html');
define('PIWIK_INCLUDE_PATH', PIWIK_DOCUMENT_ROOT);
$_GET['idSite'] = $_REQUEST['idSite'] = 1;
$_GET['period'] = $_REQUEST['period'] = 'day';
$_GET['date'] = $_REQUEST['date'] = 'today';
require PIWIK_INCLUDE_PATH . '/core/bootstrap.php';
(new Piwik\Application\Environment('cli'))->init();
Piwik\Console::initPlugins();
require __DIR__ . '/dashboard-widgets.php';
Piwik\Access::doAsSuperUser(function () {
    $model = new Piwik\Plugins\Dashboard\Model();
    $reports = [];
    foreach ($model->getAllDashboardsForUser('franklin') as $dashboard) {
        if ($dashboard['name'] !== 'WLV — acessos, abas e exportações') { continue; }
        $layout = json_decode($dashboard['layout'], true, 512, JSON_THROW_ON_ERROR);
        $changes = [];
        foreach ($layout as &$column) {
            foreach ($column as &$widget) {
                $params = $widget['parameters'];
                if (($params['containerId'] ?? '') === 'Events') {
                    $module = 'Events'; $action = 'getCategory'; $extra = [];
                } else {
                    $module = $params['module']; $action = $params['action'];
                    $extra = array_intersect_key($params, array_flip(['viewDataTable', 'idDimension']));
                }
                $fixed = wlvDashboardWidget($module, $action, $extra);
                $changes[] = ['module' => $module, 'action' => $action, 'old_id' => $widget['uniqueId'], 'registered_id' => $fixed['uniqueId']];
                $widget = $fixed;
            }
            unset($widget);
        }
        unset($column);
        $model->updateLayoutForUser('franklin', (int)$dashboard['iddashboard'], json_encode($layout));
        $reports[] = ['dashboard_id' => (int)$dashboard['iddashboard'], 'widgets' => $changes];
    }
    echo json_encode(['updated' => $reports], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . "\n";
});
