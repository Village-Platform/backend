module Admin
  module UiHelper
    # The design has four tones. Anything not listed falls back to gray.
    TONES = {
      "active" => "green", "current" => "green", "approved" => "green", "super_admin" => "green", true => "green",
      "admin" => "gold",
      "pending" => "gold", "scheduled" => "gold", "firm_admin" => "gold", "announcement" => "gold",
      "rejected" => "red", "suspended" => "red", "deleted" => "red",
      "expired" => "gray", "user" => "gray", "news" => "gray", "article" => "gray", false => "gray"
    }.freeze

    def enum_label(model, attribute, value)
      return "—" if value.blank?

      t("enums.#{model.model_name.i18n_key}.#{attribute}.#{value}", default: value.to_s.humanize)
    end

    # [[label, value], ...] for <select>
    def enum_options(model, attribute)
      model.public_send(attribute.to_s.pluralize).keys.map { |key| [ enum_label(model, attribute, key), key ] }
    end

    def badge(text, tone = "gray")
      tag.span(text, class: "badge badge-#{tone}")
    end

    def enum_badge(model, attribute, value)
      badge(enum_label(model, attribute, value), TONES.fetch(value.to_s, "gray"))
    end

    def yes_no_badge(value)
      badge(value ? "نعم" : "لا", TONES[!!value])
    end

    # Read-only inline toggle, for a boolean a row only reports. The state is carried by
    # colour and knob position, so it needs a name of its own: this replaced a cell that
    # used to read "نعم"/"لا" out loud.
    def switch(value, label: nil)
      tag.span(tag.span("", class: "switch-knob"),
               class: [ "switch", ("switch-on" if value) ],
               role: "img",
               "aria-label": label || (value ? "نعم" : "لا"))
    end

    def egp(cents)
      return "—" if cents.nil?

      "#{number_with_precision(cents / 100.0, precision: 2, strip_insignificant_zeros: true)} ج.م"
    end

    def fmt_time(time)
      time ? l(time, format: "%Y-%m-%d %H:%M") : "—"
    end

    def fmt_date(time)
      time ? l(time.to_date, format: "%Y-%m-%d") : "—"
    end

    # The design filters by enum with a tab row rather than a <select>. Other active
    # filters ride along, so switching status does not silently drop a search.
    # `aria-current` replaces the selected-option announcement the <select> used to give.
    def filter_tabs(param, options, all_label: "الكل")
      current = params[param].presence
      rows = [ [ all_label, nil ] ] + options

      tag.nav(class: "tabs", "aria-label": "تصفية") do
        safe_join(rows.map { |label, value|
          active = current == value
          link_to label, url_for(filter_params(param => value, page: nil)),
                  class: [ "tab", ("tab-on" if active) ],
                  "aria-current": (active ? "page" : nil)
        })
      end
    end

    # The autocomplete JS binds to every [data-admin-search], finds its listbox through
    # aria-controls and its live-status span through the shared parent. That contract is
    # implicit, so it lives here once rather than in five hand-written call sites.
    # Admins (reviewers) cannot reach the search endpoint, so they get the plain field.
    def search_combobox(scope, wrapper_class: "searchable-field")
      return tag.div(capture { yield({}) }, class: wrapper_class) unless current_admin.super_admin?

      results_id = "#{scope}-search-results"
      attrs = {
        role: "combobox", "aria-autocomplete": "list", "aria-expanded": "false",
        "aria-controls": results_id,
        data: { admin_search: true, search_url: admin_search_path, search_scope: scope }
      }

      tag.div(class: wrapper_class) do
        safe_join([
          capture { yield attrs },
          tag.ul(nil, id: results_id, class: "admin-search-results", role: "listbox", hidden: true),
          tag.span(nil, class: "sr-only", role: "status", "aria-live": "polite",
                   data: { search_status: true })
        ])
      end
    end

    def nav_group(label, &block)
      safe_join([ tag.p(label, class: "nav-section"), capture(&block) ])
    end

    def nav_link(label, path, icon_name, exact: false, count: nil)
      active = exact ? request.path == path : request.path.start_with?(path)
      link_to path, class: [ "nav-link", ("active" if active) ], "aria-current": (active ? "page" : nil) do
        safe_join([ icon(icon_name), tag.span(label), (tag.span(count, class: "nav-count") if count.to_i.positive?) ].compact)
      end
    end

    # The title and subtitle belong to the topbar now; the block becomes the actions row.
    # <%= page_header "التصنيفات", subtitle: "..." do %> buttons <% end %>
    def page_header(title, subtitle: nil, &block)
      content_for(:title, title) unless content_for?(:title)
      content_for(:subtitle, subtitle) if subtitle.present? && !content_for?(:subtitle)
      return "".html_safe unless block

      tag.div(capture(&block), class: "actions-row")
    end

    # Both variants ship on every page; CSS shows the one that suits the active theme.
    # An <img> cannot swap source by media query, and the server does not know the
    # OS preference when no cookie has been set.
    def brand_mark(size: 36)
      themed_image("mark", width: size, height: size)
    end

    def brand_logo(width: 150, height: 150)
      themed_image("logo", width: width, height: height)
    end

    def theme_toggle
      current = cookies[:admin_theme]
      # Inline SVG rather than ☀/☾: Cairo has neither glyph, so they fall back to whatever
      # symbol font the OS happens to carry — tofu on a bare Linux box — and they cannot
      # take currentColor the way the rest of the icon set does.
      buttons = [ [ "light", :sun, "الوضع النهاري" ], [ "dark", :moon, "الوضع الليلي" ] ].map do |value, name, label|
        button_to admin_theme_path, method: :patch, params: { theme: value },
                  class: [ "seg-btn", ("seg-on" if current == value) ], title: label,
                  aria: { label: label } do
          icon(name, size: 14)
        end
      end
      tag.div(safe_join(buttons), class: "seg")
    end

    # No cookie means "follow the operating system", which the stylesheet handles with a
    # prefers-color-scheme block; only an explicit choice pins the attribute.
    def theme_attribute
      theme = cookies[:admin_theme]
      return {} unless Admin::ThemeController::THEMES.include?(theme)

      { "data-theme" => theme }
    end

    def initials(name)
      name.to_s.split.first(2).map { |part| part[0] }.join
    end

    def empty_state(message)
      tag.div(class: "empty") do
        safe_join([ brand_mark(size: 56), tag.p(message) ])
      end
    end

    # Keeps current filters when building links (pagination, tab rows).
    #
    # Only the keys the admin screens actually filter on are carried forward. Handing
    # `request.query_parameters` straight to `url_for` lets a crafted `?host=` rewrite every
    # link on the page to another domain — the operator lands on a genuine page and the first
    # thing they click takes them off-site — and a `?controller=`/`?action=` pair reroutes
    # them or raises UrlGenerationError.
    FILTER_KEYS = %i[ q status role kind category_id payment_method subscription_plan_id deleted page per_page ].freeze

    def deleted_badge(record)
      return unless record.respond_to?(:deleted?) && record.deleted?

      badge("محذوف", "red")
    end

    def filter_params(**overrides)
      request.query_parameters.symbolize_keys.slice(*FILTER_KEYS).merge(overrides)
    end

    private

    # "<name>.png" is drawn for light surfaces, "<name>-light.png" for dark ones.
    def themed_image(name, **attrs)
      tag.span(class: "brand-mark") do
        safe_join([
          image_tag("/brand/web/#{name}.png", alt: "", class: "on-light", **attrs),
          image_tag("/brand/web/#{name}-light.png", alt: "", class: "on-dark", **attrs)
        ])
      end
    end
  end
end
