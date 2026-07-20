defmodule AponteWeb.Router do
  use AponteWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AponteWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug AponteWeb.Plugs.BasicAuth
  end

  # Loads the tenant org into assigns[:org] (404 on miss), then themes the
  # page with the org accent. Accent MUST run after the loader.
  pipeline :load_org do
    plug AponteWeb.Plugs.LoadOrg
    plug AponteWeb.Plugs.Accent
  end

  # JSON-404 variant of the loader for the :client_api scopes.
  pipeline :load_org_api do
    plug :load_org_api_json
  end

  pipeline :dj_rate_limit do
    plug AponteWeb.Plugs.RateLimit, max: 5, window_ms: 3_600_000, bucket: "tocar"
  end

  pipeline :lookup_rate_limit do
    plug AponteWeb.Plugs.RateLimit, max: 10, window_ms: 3_600_000, bucket: "meus-ingressos"
  end

  pipeline :admin_api do
    plug :accepts, ["json"]
    plug AponteWeb.Plugs.BasicAuth
  end

  # Public JSON for customer push. Keeps CSRF protection (browser sends the
  # x-csrf-token header), unlike :admin_api which relies on Basic auth instead.
  pipeline :client_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  defp load_org_api_json(conn, _opts), do: AponteWeb.Plugs.LoadOrg.load_org_api(conn, [])

  # User uploads — outside :browser (no session/CSRF for plain GETs).
  scope "/", AponteWeb do
    get "/uploads/*path", UploadController, :show
  end

  # Aponte-level pages (brand shell, platform default accent).
  scope "/", AponteWeb do
    pipe_through [:browser, AponteWeb.Plugs.Accent]

    get "/", PageController, :index
    get "/sobre", PageController, :sobre
    get "/robots.txt", SeoController, :robots
    get "/sitemap.xml", SeoController, :sitemap
  end

  # TEMPORARY: pre-multi-org global paths 301 to their /sesh/... equivalents.
  # Removal trigger: 30 days after the domain cutover (SPEC_APONTE_V1 sec. 6).
  scope "/", AponteWeb do
    pipe_through :browser

    get "/comprar", LegacyRedirectController, :comprar
    get "/compra/:id", LegacyRedirectController, :compra
    get "/meus-ingressos", LegacyRedirectController, :meus_ingressos
    get "/loja", LegacyRedirectController, :loja
    get "/avisos", LegacyRedirectController, :avisos
    get "/tocar", LegacyRedirectController, :tocar
  end

  # Admin — literal /admin scopes MUST come before any /:org_slug scope, or
  # "admin" is swallowed as an org slug (LoadOrg 404s it as reserved).
  scope "/admin", AponteWeb do
    pipe_through [:browser, :admin]

    live "/", Admin.DashboardLive, :index
    live "/edicoes/nova", Admin.EditionFormLive, :new
    live "/edicoes/:id", Admin.EditionFormLive, :edit
    live "/edicoes/:id/cortesia", Admin.CortesiaLive, :index
    live "/pedidos/:id", Admin.OrderShowLive, :show
    live "/buscar", Admin.OrderSearchLive, :index
    live "/validar", Admin.ScannerLive, :index
    live "/validar/:edition_id", Admin.ScannerLive, :index
    live "/tocar", Admin.DjApplicationsLive, :index

    live "/cupons", Admin.CouponsLive, :index
    live "/cupons/novo", Admin.CouponFormLive, :new
    live "/cupons/regras/nova", Admin.CouponRuleFormLive, :new
    live "/cupons/regras/:id", Admin.CouponRuleFormLive, :edit
    live "/cupons/:id", Admin.CouponFormLive, :edit

    live "/produtos", Admin.ProductsLive, :index
    live "/produtos/novo", Admin.ProductFormLive, :new
    live "/produtos/:id", Admin.ProductFormLive, :edit
    live "/balcao", Admin.BalcaoLive, :index
  end

  scope "/admin", AponteWeb do
    pipe_through :admin_api

    get "/push/vapid-key", Admin.PushController, :vapid_key
    post "/push/subscribe", Admin.PushController, :subscribe
    delete "/push/subscribe", Admin.PushController, :unsubscribe
  end

  # Org-scoped public pages. Literal routes above MUST come first: anything
  # under /:org_slug would otherwise swallow them (reserved slugs are the
  # second net, not the first).
  scope "/:org_slug", AponteWeb do
    pipe_through [:browser, :load_org]

    get "/", OrgController, :show
    get "/comprar", OrderController, :new
    post "/comprar", OrderController, :create
    get "/compra/:id", OrderController, :show
    get "/meus-ingressos", OrderController, :history
    get "/loja", LojaController, :index
    post "/loja", LojaController, :create
    get "/avisos", PageController, :avisos
    get "/tocar", DjController, :new
  end

  scope "/:org_slug", AponteWeb do
    pipe_through [:browser, :load_org, :lookup_rate_limit]

    post "/meus-ingressos", OrderController, :lookup
  end

  scope "/:org_slug", AponteWeb do
    pipe_through [:browser, :load_org, :dj_rate_limit]

    post "/tocar", DjController, :create
  end

  # Customer push, org-scoped: subscribe stamps org_id from the loaded org.
  scope "/:org_slug", AponteWeb do
    pipe_through [:client_api, :load_org_api]

    get "/push/vapid-key", PushController, :vapid_key
    get "/push/subscribe", PushController, :show
    post "/push/subscribe", PushController, :subscribe
    patch "/push/subscribe", PushController, :update
    delete "/push/subscribe", PushController, :unsubscribe
  end

  # Customer push, Aponte-wide (org_id nil).
  scope "/", AponteWeb do
    pipe_through :client_api

    get "/push/vapid-key", PushController, :vapid_key
    get "/push/subscribe", PushController, :show
    post "/push/subscribe", PushController, :subscribe
    patch "/push/subscribe", PushController, :update
    delete "/push/subscribe", PushController, :unsubscribe
  end
end
