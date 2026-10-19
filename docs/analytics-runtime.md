# Estatísticas do World Labour Values

O Matomo 5.13.0 está em `https://worldlabourvalues.org/estatisticas/`. O usuário administrativo é `franklin`; a senha aleatória fica somente em `/home/franklin/.local/share/server-credentials/worldlabourvalues-matomo-admin.json` (permissão 600). Nenhuma senha ou token pertence ao Git. O email está desativado, inclusive recuperação de senha; o endereço reservado do cadastro não envia mensagens.

## Como consultar as seis informações

Selecione o site **World Labour Values** e o período no topo. **World Labour Values — homologação** é separado e contém apenas ensaios da integração.

| Informação | Onde consultar | Interpretação |
| --- | --- | --- |
| País, região e cidade | Visitantes → Localizações; widgets Países e Cidades | Estimativa pela rede de origem. VPNs, operadoras e bases gratuitas limitam a precisão. |
| Origem online | Aquisição → Visão geral, Websites, Buscadores, Redes sociais e Campanhas | Referrer ausente aparece como direto. UTM identifica links de campanhas. |
| Data e horário | Visitantes → Registro de visitas e Horários | Fuso do site: `America/Sao_Paulo`; a API também fornece timestamps UTC. Horário local do visitante é uma informação diferente. |
| Duração total | Resumo das visitas e Comportamento → Eventos → `Engagement` | Duração de visita é a estimativa Matomo. A **soma dos valores** de `active_seconds` mede segundos de página ativa. |
| Tempo em cada aba | Eventos → ações → `active_seconds`, expandindo os nomes das abas | Use a coluna **Soma dos valores de eventos**. A média dos valores mede pacotes de heartbeat; não é a permanência média por sessão. |
| Arquivos exportados | Eventos → `Download` e dimensão personalizada **Nome do arquivo** | `requested`, `generated` e `failed` distinguem solicitação, geração e falha. Geração/entrega não comprova gravação no computador. |

**Downloads e links de saída no resumo padrão:** esses cartões nativos do Matomo contam cliques instrumentados como links. As seis exportações do WLV são acompanhadas pelos eventos `Download` e pela dimensão **Nome do arquivo**. Portanto, o cartão nativo pode mostrar zero mesmo quando houve exportações; para seus arquivos, consulte **Eventos → Download**, especialmente `generated`. A integração também não mede automaticamente links de saída.

O painel inicial **WLV — acessos, abas e exportações** reúne visitas, horários, países, cidades, origens, títulos das abas, eventos, arquivos e visitas recentes. Os relatórios agregados são atualizados a cada hora; o registro de visitas recebe eventos assim que chegam. O core reconhece `utm_campaign`, usando `utm_source` ou `utm_medium` como fallback de nome quando ausente; estes dois últimos não são relatórios independentes do core. A instrumentação preserva esses campos nos eventos `Acquisition / campaign_source` e `Acquisition / campaign_medium`, sem extensão paga.

As dez dimensões são de **ação**, com IDs iguais em produção (site 1) e homologação (site 2):

| ID | Campo | Descrição |
| --- | --- | --- |
| 1 | `kind` | Tipo de exportação |
| 2 | `format` | Formato |
| 3 | `method` | Base de dados |
| 4 | `country` | País selecionado |
| 5 | `partner` | Parceiro selecionado |
| 6 | `indicator` | Indicador |
| 7 | `years` | Período selecionado |
| 8 | `sector` | Setor selecionado |
| 9 | `release` | Versão dos dados |
| 10 | `filename` | Nome do arquivo |

## Privacidade e limites

- O coletor força modo sem cookies e a integração do painel desativa cookies no navegador. Cookies administrativos de login têm finalidade diferente e ficam restritos à interface de estatísticas.
- DNT é respeitado também no servidor. A preferência de desativação e GPC são atendidos pela integração no painel. Não são configurados User ID, gravação de tela ou identificação nominal.
- O IP completo é usado apenas em memória para consultar a base local; a gravação mascara os últimos dois octetos IPv4 (80 bits finais no IPv6). Não há consulta externa por visitante. A base **DB-IP City Lite** é atualizada mensalmente pelo agendador Matomo. Crédito: [DB-IP](https://db-ip.com/db/lite.php).
- A aplicação Matomo não mantém access log Apache, e a rota `/estatisticas/` no Nginx usa `access_log off`. Os demais logs originais do servidor seguem suas próprias configurações. URLs de referrer têm query removida no Matomo; a instrumentação também deve limitar URLs e metadados ao contrato público do painel.
- Logs analíticos detalhados são removidos após 90 dias; relatórios agregados são mantidos. Os backups locais têm retenção de sete dias, portanto uma cópia de segurança pode conter detalhes por até cerca de 97 dias. Não há histórico retroativo de tempo por aba anterior à instrumentação.
- Sem cookies de identificação, visitantes únicos, recorrência e sessões são estimativas. Bloqueadores, falha de rede, fechamento abrupto e DNT/opt-out reduzem a cobertura. Tempo de página visível não comprova atenção.

## Infraestrutura isolada

Tudo reside em `/srv/worldlabourvalues-analytics`. Docker Compose cria os containers `wlv-analytics-app` e `wlv-analytics-db`. O HTTP escuta **somente `127.0.0.1:8093`**. MariaDB não publica porta e participa apenas da rede Docker interna. O app participa também de uma rede para atualizações de geolocalização e definições. Limites: app 2 GiB/1,5 CPU e banco 1 GiB/1 CPU.

Imagens oficiais fixadas por digest:

```text
matomo:5.13.0-apache@sha256:8e6bdd396496a98e4011cfbdc4be996d9259cbd1f09e0651b6058bb9a5984e13
mariadb:11.8.9@sha256:2d2f4095530294735a857cfe22bb101e19b0849b416911c796ec4aa81b164a62
```

O proxy remove `/estatisticas/` e sobrescreve `Host`/`X-Forwarded-Host` com `worldlabourvalues.org`, `X-Forwarded-Proto` com `https`, `X-Forwarded-Uri` com `/estatisticas` e `X-Forwarded-For` com o IP real da conexão. O Matomo usa `proxy_uri_header=1`, `assume_secure_protocol=1`, `force_ssl=1` e verifica o host confiável. Não retransmita um `X-Forwarded-For` recebido do cliente como se fosse confiável.

Os serviços são independentes de Shiny e dos demais sites:

```bash
sudo systemctl status worldlabourvalues-analytics.service
sudo systemctl list-timers 'worldlabourvalues-analytics-*'
sudo systemctl start worldlabourvalues-analytics-archive.service
sudo journalctl -u worldlabourvalues-analytics-archive.service -n 40
sudo systemctl start worldlabourvalues-analytics-backup.service
```

O archive usa o agendador Matomo, que também executa limpeza de logs e atualização da geobase. Para investigar relatório sem criar um token persistente, a API local usa o acesso administrativo já necessário ao Docker:

```bash
# A partir do checkout revisado do aplicativo:
sudo python3 scripts/analytics-runtime/query-api.py '{"method":"Live.getLastVisitsDetails","idSite":2,"period":"day","date":"today","filter_limit":10}'
sudo python3 scripts/analytics-runtime/query-api.py '{"method":"Events.getAction","idSite":2,"period":"day","date":"today","secondaryDimension":"eventName","expanded":true}'
```

Esse helper não é um endpoint HTTP e deve permanecer fora do document root. Para integrações remotas use token de aplicação de duração limitada, enviado por POST ou Authorization; nunca em URL, log ou repositório. `check-backend.py` testa autenticação HTTP com token temporário em memória e eventos identificados apenas no site 2.

## Backup, restauração e atualização

O timer diário, às 04:20 UTC com pequeno atraso aleatório, gera `matomo.sql.gz`, `configuration.tar.gz` e `complete.json` em `backups/<UTC>`. A cópia é transacional, com arquivos privados; contém segredos de configuração. Ela protege contra alterações acidentais, mas está no mesmo servidor e não substitui uma cópia externa autorizada.

Para restaurar, interrompa os timers e a aplicação Matomo, preserve o estado atual em outro diretório operacional de backup e recrie **somente esta instalação** com os mesmos digests. Restaure o arquivo de configuração/segredos, inicie apenas o banco e importe `matomo.sql.gz` para o banco `matomo`. Só então inicie o app e valide login, IDs, DNT e coleta no site 2 antes de reativar o proxy/timers. A restauração apaga/substitui dados e exige escolher explicitamente o backup correto; os scripts não executam isso automaticamente. Não altere o banco ou serviço Shiny dos outros sites.

Para atualizar, faça backup completo, revise versões oficiais e novos digests no Compose, ensaie a compatibilidade em campanha própria, atualize os arquivos operacionais e execute `docker compose up -d`. A imagem oficial conserva o volume de dados/configuração; migrações de banco podem exigir restaurar banco e configuração em conjunto para voltar à versão anterior. Nunca use `docker compose down -v`.

## Recriar a instalação

`initialize-runtime.py` recusa destinos ou credenciais existentes. Ele prepara diretórios e segredos fortes. Depois, `docker compose up -d` sobe banco e app; `bootstrap.php` recebe os segredos exclusivamente pelo stdin de `docker exec -i`. Ele usa APIs do instalador e instala os plugins oficiais sem enviar email. `--resume` aceita apenas instalação ainda marcada como incompleta. `configure.php` configura as dez dimensões, a base geográfica e o dashboard sem substituir dimensões incompatíveis. Remova `secrets/bootstrap.json` após sucesso e mantenha somente a credencial administrativa privada e os segredos operacionais do banco. Ajuste ownership para `www-data` nos diretórios graváveis `html/config`, `html/tmp` e `html/misc` após comandos CLI executados como root.

Fontes oficiais consultadas: [Docker](https://matomo.org/faq/how-to-install/install-matomo-with-docker/), [proxy e subpasta](https://matomo.org/faq/how-to-install/faq_98/), [código Matomo 5.13.0](https://github.com/matomo-org/matomo/tree/5.13.0), [definições das imagens oficiais](https://github.com/docker-library/official-images/tree/master/library).
