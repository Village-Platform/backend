module Admin
  module AuthenticatorHelper
    # The setup QR code as inline SVG. It carries the secret, so it is drawn here and never sent to a
    # third-party QR service. The SVG holds only path data and the translated label.
    def authenticator_qr(uri)
      RQRCode::QRCode.new(uri).as_svg(
        module_size: 5, use_path: true, viewbox: true, standalone: true,
        svg_attributes: { role: "img", "aria-label": t("admin.authenticators.qr_label") }
      ).html_safe # rubocop:disable Rails/OutputSafety
    end

    # "JBSW Y3DP EHPK 3PXP": easier to type into an authenticator app than one long run.
    def grouped_secret(secret)
      secret.scan(/.{1,4}/).join(" ")
    end
  end
end
