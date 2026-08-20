# frozen_string_literal: true

# Request-scoped state, reset by Rails between requests.
#
# Only holds what genuinely cannot be passed as an argument. `request_origin` is
# here because whether a storage URL is reachable depends on how the browser
# reached *us*, and that has to be known deep inside serializers that never see
# the request.
class Current < ActiveSupport::CurrentAttributes
  attribute :request_origin
end
