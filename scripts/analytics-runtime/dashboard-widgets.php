<?php
/** Resolve widgets pelo registro público Matomo; IDs não podem ser inventados. */
function wlvDashboardWidget(string $module, string $action, array $extra = []): array
{
    static $widgets = null;
    $widgets ??= Piwik\Plugins\API\API::getInstance()->getWidgetMetadata(1);
    foreach ($widgets as $widget) {
        $parameters = $widget['parameters'];
        if (($widget['module'] ?? '') !== $module || ($widget['action'] ?? '') !== $action) {
            continue;
        }
        foreach ($extra as $key => $value) {
            if ((string)($parameters[$key] ?? '') !== (string)$value) {
                continue 2;
            }
        }
        return ['uniqueId' => $widget['uniqueId'], 'parameters' => $parameters];
    }
    throw new RuntimeException('Widget não registrado: ' . $module . '.' . $action . ' ' . json_encode($extra));
}
