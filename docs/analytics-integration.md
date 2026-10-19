# Integração de estatísticas no painel

A integração usa Matomo no próprio servidor, sem cookies de identificação e
com a opção **Privacidade e estatísticas** no rodapé e no menu da engrenagem.
As sete abas, os controles,
os dados e o conteúdo dos arquivos permanecem funcionais com a coleta
desativada ou com o Matomo indisponível. O script é carregado de forma
assíncrona pelo mesmo domínio. Não há banner de consentimento nesta configuração.

## O que é medido

- Cada entrada e troca entre Sobre, Mapa, País, Indicadores, Comércio, Download
  e Publicações produz uma visualização com URL virtual `/?tab=...`.
- A primeira visualização conserva apenas parâmetros conhecidos de campanha,
  com tamanho e caracteres limitados. O referrer enviado contém somente a
  origem, sem caminho nem query. O redirecionamento do subdomínio registra
  `Acquisition / entry_origin / panel`; `campaign_source` e `campaign_medium`
  guardam os respectivos parâmetros como eventos.
- `Engagement / active_seconds / <aba>` envia segundos de página visível e
  com foco, em intervalos de 15 segundos e nas mudanças de aba, foco e
  visibilidade. Após 120 segundos sem interação, a contagem pausa. Mudança de
  foco entre janelas comunica a pausa, sem identificador persistente. Use a
  **soma dos valores dos eventos** para obter segundos ativos por aba ou no
  conjunto; a média dos pacotes não equivale à média por visita. A duração
  padrão Matomo mede o intervalo entre ações e pode diferir deste total.
- Os seis tipos de exportação emitem `Download / requested`, `generated` e,
  quando necessário, `failed`. São as planilhas agregada, bilateral e
  multilateral, o CSV de Indicadores e as duas planilhas de Comércio. Dimensões
  registram nome, formato, seleções e versão dos dados. `generated` significa
  arquivo escrito com sucesso para entrega; não confirma gravação no computador.
  Consulte **Eventos → Download** ou **Nome do arquivo**. O relatório nativo
  **Downloads** do Matomo mede outro tipo de ação (`trackLink`) e não é usado
  por estas exportações Shiny; um zero nesse relatório não significa ausência
  de arquivos gerados.

Datas, locais, origem e instruções dos relatórios estão em
[analytics-runtime.md](analytics-runtime.md). Tráfego com bloqueadores, DNT,
GPC ou desativação não compõe os relatórios. Localização, visitantes únicos e
tempo de atenção são estimativas. A medição começa na ativação da integração;
não há reconstrução retroativa do tempo por aba.

## Preferência do visitante

O botão no rodapé ou nas configurações abre um diálogo traduzido junto da
aplicação. O segundo acesso está disponível também no Mapa, que oculta o
rodapé para aproveitar a tela. A desativação
interrompe o envio e descarta eventos pendentes; downloads continuam normais.
Somente o booleano `wlv_analytics_optout` é salvo no armazenamento local, para
lembrar a escolha no mesmo navegador. Não é um identificador de visitante.
Sem acesso a esse armazenamento, a preferência vale para o documento atual.
A integração respeita também Do Not Track e Global Privacy Control. Cookies
funcionais já existentes, como idioma e aba, não fazem parte da identificação
analítica. O login do administrador Matomo é separado e usa sua própria sessão.

## Configuração externa e código

O wrapper `/srv/worldlabourvalues/bin/R` exporta
`WLV_ANALYTICS_CONFIG=/etc/worldlabourvalues/analytics.json`. O arquivo
operacional pertence a `root:shiny`, modo 640, e define `enabled`, `site_id`,
`tracker_url`, `script_url`, `dimensions` e `release`. Produção é site **1**;
homologação é site **2**. IDs de dimensões são iguais em ambos. Não há senha ou
token neste arquivo nem na configuração enviada ao navegador. Segredos
administrativos permanecem no arquivo privado indicado no guia do runtime.

`utils/analytics.R` valida essa configuração; `www/wlv-analytics.js` controla
navegação, tempo, privacidade e envio. `utils/analytics_downloads.R` preserva os
resultados dos escritores R e emite mensagens Shiny com metadados limitados.
Nenhum download espera uma chamada HTTP ao Matomo. Quando a configuração está
ausente ou inválida, a coleta fica desativada. A chave `enabled: false` permite
desativá-la operacionalmente, após reiniciar somente `worldlabourvalues.service`.

## Publicações e preservação da integração

A fonte oficial do aplicativo é a branch `main` de
[`rodrigoesborges/labourvaluesdatapanel` no GitLab](https://gitlab.com/rodrigoesborges/labourvaluesdatapanel).
Uma alteração publicada deve estar incorporada nessa branch, e o manifesto
operacional deve registrar o mesmo commit entregue ao servidor. Não publique
uma cópia de outra origem sem reconciliar as alterações existentes.

A instrumentação inicial de 13/09/2026 foi publicada como
`/srv/worldlabourvalues/releases/20260913-analytics`, a partir do commit
`07609d002b3da17c88ad0c49e9a7d1d0ff5043ce` de uma branch local. A campanha
`temp/analytics-20260913` registra que não houve push para o GitHub. A release
`20260919` veio de um novo clone do GitLab e não continha essa instrumentação.
A restauração incorpora os arquivos à linha atual do GitLab, preservando
as melhorias posteriores de interface e armazenamento.

Para publicar uma próxima versão:

1. Prepare uma release separada a partir do commit revisado do GitLab e registre
   seus hashes. Preserve os dados científicos existentes; não regenere dados
   como parte de uma atualização de estatísticas.
2. Execute os testes abaixo em uma campanha ativa. No navegador, use um Shiny
   candidato e um proxy locais, com configuração externa que selecione o site
   Matomo **2**. Nunca execute a suíte completa contra o site de produção.
3. Preserve `/etc/worldlabourvalues/analytics.json`, a rota Nginx `/estatisticas/`
   e `WLV_ANALYTICS_CONFIG` no wrapper R. Preserve também `WLV_STORAGE_ROOT`
   para os diretórios graváveis de cache e downloads. O código da release deve
   conter os helpers R, scripts, estilos e traduções de estatísticas.
4. Guarde a configuração anterior e troque a release somente no serviço
   `worldlabourvalues.service`. O serviço Shiny compartilhado e os contêineres
   Matomo são independentes. Sessões abertas podem precisar de reconexão.
5. Execute o smoke público identificado por campanha e confirme na API Matomo
   que os eventos chegaram ao site **1**. Um HTTP 204 do coletor, sozinho,
   não comprova que o registro foi persistido.

Para retornar, use o backup feito imediatamente antes dessa publicação e
reinicie somente o serviço do aplicativo. Não reutilize automaticamente o
backup da migração de 13/09: ele precede melhorias posteriores. Não remova
volumes, dados, configuração ou backups Matomo ao reverter o painel.

## Verificações reproduzíveis

Os testes manuais `check-analytics-state.cjs`, `check-analytics-config.R` e
`check-analytics-ui.R` verificam relógio, sinais de privacidade, configuração e
traduções. `test-analytics-downloads.R` verifica metadados, deduplicação e a
preservação de resultados/erros dos downloads. `check-analytics-browser.cjs`
exige site 2 e cobre navegação real, seis exportações, tempo em primeiro plano,
opt-out, recarga, DNT/GPC e indisponibilidade do coletor. O ensaio administrativo
separado faz login/logout, verifica widgets e bloqueio de relatórios anônimos,
sem salvar senha, token ou estado autenticado no relatório. As evidências
sanitizadas e a reconciliação com os registros Matomo ficam na campanha.
O smoke após publicação gera uma visita no site 1 com campanha
`analytics-production-validation-...`; ela é um teste operacional identificado,
que pode ser excluído da análise por filtro de campanha. Os ensaios completos
permanecem separados no site 2.

Os testes exigem `WLV_CAMPAIGN_ROOT=<checkout>/temp/<id>` com manifesto ativo,
e `TEMP`, `TMP` e `TMPDIR` apontando para seu `scratch/`. Quando o checkout de
validação fica em `temp/<campanha>/worktrees/panel`, crie sua campanha interna
em `worktrees/panel/temp/<id>`; todos os artefatos continuam dentro da campanha
principal. Execute os testes a partir desse checkout. Dependências de navegador
ficam em `scratch/browser`; os relatórios ficam em `results/`.
