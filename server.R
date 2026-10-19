function(input, output, session) {
  RV <- reactiveValues()
  wlv_analytics_download_bind(input, session, wlv_analytics_config)
  lapply(modules_server, function(module) module(input, output, RV, session))
  wlv_language_delivery(input, session, wlv_language_messages)
  observeEvent(input$about_map, updateNavbarPage(session, "main_nav", selected = "map"))
  observeEvent(input$about_indicators, updateNavbarPage(session, "main_nav", selected = "indicators"))
}
