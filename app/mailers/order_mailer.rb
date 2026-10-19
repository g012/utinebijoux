class OrderMailer < ApplicationMailer
  def confirmation(order)
    @order = order
    mail(to: order.customer_email, subject: "Votre commande #{order.number} — #{Shop.name}")
  end
  def new_sale(order)
    @order = order
    mail(to: Shop.admin_email, subject: "Une nouvelle création adoptée ! #{order.number}")
  end
end
