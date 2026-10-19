setup_panel <- tagList(
  tags$div(style = "display:none", `aria-hidden` = "true",
    selectInput("l", NULL, choices = wlv_languages()$value[wlv_languages()$available], selected = default_language, selectize = FALSE)),
  tags$div(id = "wlv-language", class = "wlv-language-control",
    tags$div(class = "wlv-language-buttons",
      tags$button(id = "language_toggle", class = "btn wlv-language", type = "button",
        lang = "en", `data-language` = "English", `aria-label` = "Switch to English", "English"),
      tags$span(class = "wlv-language-divider", `aria-hidden` = "true", "|"),
      tags$button(id = "language_menu_toggle", class = "btn wlv-language-arrow", type = "button",
        `aria-label` = "Escolher idioma", `aria-haspopup` = "menu", `aria-controls` = "language_menu",
        `aria-expanded` = "false", tags$span(class = "wlv-language-chevron", `aria-hidden` = "true"))),
    tags$ul(id = "language_menu", class = "wlv-language-menu", role = "menu", hidden = NA,
      `aria-labelledby` = "language_menu_toggle",
      lapply(seq_len(nrow(wlv_languages())), function(i) {
        language <- wlv_languages()[i, ]
        tags$li(role = "none", tags$button(type = "button", role = "menuitemradio", tabindex = "-1",
          lang = language$code, `data-language` = language$value, `data-available` = tolower(language$available),
          `aria-checked` = tolower(language$value == "English"),
          `aria-disabled` = if (!language$available) "true" else NULL,
          tags$span(language$value),
          if (!language$available) tags$small(class = "wlv-language-soon", "Em breve")))
      }))),
  tags$details(id = "wlv-settings", class = "wlv-settings",
    tags$summary(id = "settings_toggle", `aria-label` = "Configurações", icon("gear")),
    div(class = "wlv-settings-panel",
      tags$h2(l("app.bases")),
      selectizeInput("bases", label = l("app.bases"), choices = list_methods,
        selected = intersect(init_bases, list_methods), multiple = TRUE, width = "100%",
        options = list(plugins = list("remove_button"))),
      actionButton("info_bases", label = l("app.method_info"), icon = icon("circle-info")),
      tags$p(wlv_analytics_privacy_button("wlv-privacy-open-settings"))))
)
SERVER <- function(IP, OP, RV, SESSION) {
  RV$bases <- reactive({
    selected <- intersect(IP$bases, list_methods)
    if (length(selected)) selected else intersect(init_bases, list_methods)
  })
  observeEvent(IP$bases, {
    if (!length(IP$bases)) updateSelectizeInput(SESSION, "bases", selected = intersect(init_bases, list_methods))
  }, ignoreNULL = FALSE)
  OP$bases_info_text <- renderUI({
      lapply(seq_len(nrow(meta_methods)), function(i) {
        tags$section(class = "wlv-method-info",
          tags$h3(meta_methods$code[i]),
          tags$p(tags$strong(lb("ps.base_source", IP$l)), " ", meta_methods$source[i]),
          tags$p(lb(paste0("DESC.", meta_methods$code[i]), IP$l)))
      })
  })
  observeEvent(IP$info_bases, {
    showModal(modalDialog(
      title = l("app.method_info"), size = "l", easyClose = TRUE,
      uiOutput("bases_info_text"), footer = modalButton(l("app.close"))
    ))
  })
}
modules_server[[length(modules_server) + 1L]] <- SERVER
