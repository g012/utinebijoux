Rails.application.routes.draw do
  root "pages#home"
  get "boutique", to: "products#index", as: :products
  get "bijoux/:slug", to: "products#show", as: :product
  get "a-propos", to: "pages#about", as: :about
  get "contact", to: "pages#contact", as: :contact
  get "informations/:page", to: "pages#legal", as: :legal
  get "sitemap.xml", to: "pages#sitemap", defaults: { format: :xml }, as: :sitemap
  resource :cart, path: "panier", only: [ :show ] do
    post :checkout
    delete :cancel_checkout
  end
  resources :cart_items, path: "panier/articles", only: [ :create, :update, :destroy ]
  get "commandes/:token", to: "orders#show", as: :order
  post "stripe/webhook", to: "stripe_webhooks#create"
  resource :session, only: [ :new, :create, :destroy ]
  resources :passwords, param: :token, only: [ :new, :create, :edit, :update ]
  namespace :admin do
    root "dashboard#index"
    resources :products, except: [ :show ]
    resources :orders, only: [ :index, :show ]
  end
  get "up", to: "rails/health#show", as: :rails_health_check
end
