;; ~/.config/nyxt/config.lisp
;; Eldritch theme for Nyxt
;; Palette source: github.com/eldritch-theme/eldritch

(define-configuration browser
  ((theme (make-instance 'theme:theme
    :dark-p t
    :background-color    "#212337"  ;; Sunken Depths Grey (bg)
    :on-background-color "#ebfafa"  ;; Lighthouse White (fg)
    :primary-color       "#323449"  ;; Shallow Depths Grey (current line / surface)
    :on-primary-color    "#ebfafa"  ;; Lighthouse White
    :secondary-color     "#7081d0"  ;; The Old One Purple (comments / muted)
    :on-secondary-color  "#ebfafa"
    :accent-color        "#04d1f9"  ;; Watery Tomb Blue (cyan / primary accent)
    :on-accent-color     "#212337"
    :success-color       "#37f499"  ;; Eldritch Green
    :warning-color       "#e9f941"  ;; Eldritch Yellow
    :highlight-color     "#f265b5"  ;; Eldritch Magenta/Pink
    :codeblock-color     "#9071f4"  ;; Eldritch Purple/Blue
    :text-color          "#ebfafa"
    :contrast-text-color "#212337"))))