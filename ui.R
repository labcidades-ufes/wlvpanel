function(request) {
initial <- wlv_initial_language(request)
message <- wlv_language_messages(initial$language)
initial$labels <- message$labels
initial$phrases <- message$phrases
initial$fingerprint <- message$fingerprint
initial$languages <- wlv_languages()
tagList(
  tags$div(hidden = NA, textInput("wlv_language_bootstrap", NULL, value = initial$fingerprint)),
  tags$head(tags$script(HTML(paste0("window.wlvInitialLanguage = ", jsonlite::toJSON(initial, auto_unbox = TRUE, null = "null"), ";")))),
  tags$head(wlv_analytics_head(wlv_analytics_config)),
  tags$header(class = "wlv-topbar",
    tags$a(class = "wlv-brand", href = "https://worldlabourvalues.org/", `aria-label` = "WLVD — World Labour Values Database",
      tags$img(src = "a_batallar_ideas.png", alt = "", height = "40", width = "40"),
      tags$span(class = "wlv-brand-name", "WLVD", tags$small(l("app.title")))),
    tags$div(class = "wlv-topbar-actions", setup_panel)
  ),
  do.call(navbarPage, c(list(
  id = "main_nav", selected = "about", theme = shinytheme("simplex"),
  collapsible = TRUE, windowTitle = "WLVD | World Labour Values Database",
  title = tags$span(id = "wlv-mobile-current", `aria-live` = "polite", l("tab_name.about")),
  header = tagList(
    tags$head(
      tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
      tags$link(rel = "icon", href = "favicon.ico"),
      wlv_shared_assets
    ),
    tags$a(href = "#wlv-content", class = "wlv-skip", l("app.skip")),
    tags$div(id = "wlv-content", tabindex = "-1"),
    tags$div(class = "wlv-busy", role = "status", `aria-live` = "polite", l("app.loading"))
  ),
  footer = tags$footer(class = "wlv-footer",
    "World Labour Values Task Force", tags$span("CC BY-NC-SA 4.0"), wlv_analytics_privacy_button())
), modules_ui)),
  wlv_analytics_privacy_ui()
)
}
