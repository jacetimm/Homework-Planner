# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :https, :data
    policy.object_src  :none
    policy.script_src  :self, :unsafe_inline  # unsafe_inline needed until inline scripts are refactored to use nonces
    policy.style_src   :self, :unsafe_inline  # Tailwind utilities may inject inline styles
    policy.connect_src :self
    policy.frame_src   :none
    policy.base_uri    :self
    policy.form_action :self, "https://accounts.google.com"  # OAuth redirects
  end

  # Report violations without enforcing the policy during beta.
  # Once inline scripts are moved to nonce-based, switch to enforcing.
  config.content_security_policy_report_only = true
end
