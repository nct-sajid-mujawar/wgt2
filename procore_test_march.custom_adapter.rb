{
  title: 'Procore',

  connection: {
    fields: [
      { name: 'environment', optional: false,
        hint: "View <a href='https://developers.procore.com/documentation/" \
          "development-environments' target='_blank'>Procore documentation" \
          '</a> for more information on Environments.',
        control_type: 'select',
        pick_list: [
          ['Production', 'api.procore.com'],
          ['Monthly Sandbox', 'api-monthly.procore.com'],
          ['Development Sandbox', 'sandbox.procore.com']
        ],
        toggle_hint: 'Select from list',
        toggle_field: {
          name: 'environment',
          label: 'Environment',
          type: :string,
          control_type: 'text',
          optional: false,
          toggle_hint: 'Use custom value',
          hint: 'E.g. api.procore.com'
        } },
      { name: 'client_id', optional: false,
        hint: "View the <a href='https://developers.procore.com/documentation" \
        "/building-apps-intro' target='_blank'>Procore connection guide" \
        '</a> for information on obtaining Client ID.' },
      { name: 'client_secret', control_type: 'password', optional: false,
        hint: "View the <a href='https://developers.procore.com/documentation" \
        "/building-apps-intro' target='_blank'>Procore connection guide" \
        '</a> for information on obtaining Client secret.' },
      { name: 'company_id', optional: false,
        hint: 'Provide company ID' }
    ],

    authorization: {
      type: 'custom_auth',

      acquire: lambda do |connection|
        url = case connection['environment']
              when 'api.procore.com'
                'login.procore.com'
              when 'sandbox.procore.com'
                'login-sandbox.procore.com'
              when 'api-monthly.procore.com'
                'login-sandbox-monthly.procore.com'
              else
                connection['environment']
              end

        post("https://#{url}/oauth/token").
          params(client_id: connection['client_id'],
                 client_secret: connection['client_secret'],
                 grant_type: 'client_credentials').
          request_format_www_form_urlencoded
      end,

      refresh_on: [401, 403],

      refresh: lambda do |connection|
        url = case connection['environment']
              when 'api.procore.com'
                'login.procore.com'
              when 'sandbox.procore.com'
                'login-sandbox.procore.com'
              when 'api-monthly.procore.com'
                'login-sandbox-monthly.procore.com'
              else
                connection['environment']
              end

        post("https://#{url}/oauth/token").
          params(grant_type: 'client_credentials',
                 client_id: connection['client_id'],
                 client_secret: connection['client_secret']).
          request_format_www_form_urlencoded
      end,

      apply: lambda do |connection|
        unless current_url.include? 's3.amazonaws.com'
          if connection['company_id'].present?
            headers('Authorization' => "Bearer #{connection['access_token']}",
              'Procore-Company-Id' => connection['company_id'])
          else
            headers('Authorization' => "Bearer #{connection['access_token']}")
          end
        end
      end
    },

    base_uri: lambda do |connection|
    case connection['environment']
      when 'api.procore.com'
        'https://api.proco/e.com/rest/v1.0/'
      when 'sandbox.procore.com'
        'https://sandbox.procore.com/rest/v1.0/'
      when 'api-monthly.procore.com'
        'https://api-sandbox-monthly.procore.com/rest/v1.0'
      else
      connection['environment']
      end
    end
  },

  test: lambda do |_connection|
    get('projects').
      params(
        'company_id': _connection['company_id']
      ).
      after_error_response(/.*/) do |_code, body, _header, message|
        error("#{message}: #{body}")
      end
  end,

  custom_action: true,
  custom_action_help: {
    body: 'Build your own Procore action with a HTTP request. ' \
    'The request will be authorized with your Procore connection.',
    learn_more_url: 'https://developers.procore.com/reference/rest/v1/authentication',
    learn_more_text: 'Procore API documentation'
  },

  methods: {
    # This method is for Custom action
    make_schema_builder_fields_sticky: lambda do |schema|
      schema.map do |field|
        if field['properties'].present?
          field['properties'] = call('make_schema_builder_fields_sticky',
                                     field['properties'])
        end
        field['sticky'] = true

        field
      end
    end,

    # Formats input/output schema to replace any special characters in name,
    # without changing other attributes (method required for custom action)
    format_schema: lambda do |input|
      input&.map do |field|
        if (props = field[:properties])
          field[:properties] = call('format_schema', props)
        elsif (props = field['properties'])
          field['properties'] = call('format_schema', props)
        end
        if (name = field[:name])
          field[:label] = field[:label].presence || name.labelize
          field[:name] = name.
                           gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        elsif (name = field['name'])
          field['label'] = field['label'].presence || name.labelize
          field['name'] = name.
                            gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        end

        field
      end
    end,

    # Formats payload to inject any special characters that previously removed
    format_payload: lambda do |payload|
      if payload.is_a?(Array)
        payload.map do |array_value|
          call('format_payload', array_value)
        end
      elsif payload.is_a?(Hash)
        payload.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/__\w+__/) do |string|
            string.gsub(/__/, '').decode_hex.as_utf8
          end
          if value.is_a?(Array) || value.is_a?(Hash)
            value = call('format_payload', value)
          end
          hash[key] = value
        end
      end
    end,

    # Formats response to replace any special characters with valid strings
    # (method required for custom action)
    format_response: lambda do |response|
      response = response&.compact unless response.is_a?(String) || response
      if response.is_a?(Array)
        response.map do |array_value|
          call('format_response', array_value)
        end
      elsif response.is_a?(Hash)
        response.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
          if value.is_a?(Array) || value.is_a?(Hash)
            value = call('format_response', value)
          end
          hash[key] = value
        end
      else
        response
      end
    end,

    get_url: lambda do |input|
      if %w[company_user project_user company_person project_person
            project_vendor].include? input['object']
        objects = input['object'].split('_')
        "#{objects[0].pluralize}/#{input.delete(objects[0] + '_id')}/" \
        "#{objects[1]&.pluralize}"
      elsif input['object'] == 'company_vendor_insurance'
        "companies/#{input.delete('company_id')}/vendors/" \
        "#{input.delete('vendor_id')}/insurances"
      elsif %w[company_vendor_inactive company_user_inactive project_user_inactive
               company_person_inactive project_person_inactive
               project_vendor_inactive].include? input['object']
        objects = input['object'].split('_')
        "#{objects[0].pluralize}/#{input.delete(objects[0] + '_id')}/" \
        "#{objects[1]&.pluralize}/inactive"
      elsif input['object'] == 'company_vendor'
        'vendors'
      elsif input['object'] == 'user_project_role'
        project_id = input.delete('project_id')
        "projects/#{project_id}/user_project_roles"
      else
        input['object']&.pluralize
      end
    end,

    check_default_company: lambda do |connection|
      optional = connection['company_id'].present?
      [
        { name: 'company_id', label: 'Company',
          type: 'string', optional: optional,
          default: connection['company_id'],
          control_type: 'select',
          extends_schema: true,
          pick_list: 'company_list',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'company_id', label: 'Company ID',
            type: :string,
            control_type: 'text',
            extends_schema: true, change_on_blur: true,
            optional: optional,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the company.'
          } }
        ]
    end,

    get_company_id: lambda do |connection, company_id|
      if company_id.include?("{_('data.") || company_id.blank? ||
         company_id.include?('pill_type')
        connection['company_id']
      else
        company_id
      end
    end,

    format_date_time_range: lambda do |input|
      "#{input['from']}...#{input['to']}"
    end,

    generate_custom_field_output: lambda do |input|
      next [] if input['custom_fields'].blank?

      schema = input['custom_fields'].split(',').map do |custom_field|
        field = custom_field.split('#')

        case field[0]
        when 'lov_entries'
          { name: "custom_field_#{field[1]}", type: 'array', of: 'object',
            label: field[2],
            properties: [
              { name: 'id' },
              { name: 'label' }
            ] }
        when 'lov_entry'
          { name: "custom_field_#{field[1]}", type: 'object', label: field[2],
            properties: [
              { name: 'id' },
              { name: 'label' }
            ] }
        when 'datetime'
          { name: "custom_field_#{field[1]}", label: field[2], type: 'date_time' }
        when 'boolean'
          { name: "custom_field_#{field[1]}", label: field[2], type: 'boolean' }
        else
          { name: "custom_field_#{field[1]}", label: field[2] }
        end
      end

      [{ name: 'custom_fields', type: 'object', properties: schema }]
    end,

    generate_custom_field_input: lambda do |input|
      next [] if input['custom_fields'].blank?

      get("custom_field_definitions?company_id=#{input['company_id']}&view=extended").
        map do |custom_field|
          if input['custom_fields'].split(',').include? "#{custom_field['data_type']}##{custom_field['id']}##{custom_field['label']}"
            case custom_field['data_type']
            when 'lov_entries'
              { name: "custom_field_#{custom_field['id']}", sticky: true,
                label: custom_field['label'],
                type: 'string', control_type: 'multiselect',
                hint: 'Select custom fields of the object.',
                pick_list: custom_field['custom_field_lov_entries'].map do |option|
                  [option['label'], option['id']]
                end,
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: "custom_field_#{custom_field['id']}",
                  label: custom_field['label'],
                  optional: true,
                  type: 'string',
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Multiple values separated by comma e.g. key1,key2'
                } }
            when 'lov_entry'
              { name: "custom_field_#{custom_field['id']}", sticky: true,
                label: custom_field['label'],
                type: 'string', control_type: 'select',
                hint: 'Select custom fields of the object.',
                pick_list: custom_field['custom_field_lov_entries'].map do |option|
                  [option['label'], option['id']]
                end,
                delimiter: ',',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: "custom_field_#{custom_field['id']}",
                  label: custom_field['label'],
                  optional: true,
                  type: 'string',
                  control_type: 'text',
                  toggle_hint: 'Use custom value'
                } }
            when 'datetime'
              { name: "custom_field_#{custom_field['id']}", sticky: true,
                label: custom_field['label'], type: 'date_time' }
            when 'boolean'
              { name: "custom_field_#{custom_field['id']}",
                label: custom_field['label'], sticky: true,
                type: 'boolean', control_type: 'checkbox',
                render_input: 'boolean_conversion',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: "custom_field_#{custom_field['id']}",
                  label: custom_field['label'],
                  type: 'string', control_type: 'text',
                  render_input: 'boolean_conversion',
                  optional: true,
                  toggle_hint: 'Use custom value',
                  hint: 'Allowed values are true, false'
                } }
            else
              { name: "custom_field_#{custom_field['id']}", sticky: true,
                label: custom_field['label'] }
            end
          end
        end&.compact
    end,

    format_request_payload: lambda do |input|
      if input['object'] == 'project'
        { company_id: input.delete('company_id'),
          project: input.except('object') }
      elsif input['object'] == 'company_vendor'
        { company_id: input.delete('company_id'),
          vendor: input.except('object') }
      elsif input['object'] == 'company_vendor_insurance'
        { insurance: input['insurance'] }
      elsif %w[company_person project_person project_vendor].include? input['object']
        { input['object'].split('_')[1] => input.except('object', 'company_id',
                                                        'project_id') }
      elsif %w[company_user project_user].include? input['object']
        payload = { input['object'].split('_')[1] =>
          input.except('object', 'company_id', 'project_id') }
        if input['avatar'].present?
          payload['user[avatar]'] = [input.delete('avatar'), 'file', 'file_name']
        end
        payload
      elsif %w[folder file].include? input['object']
        payload = { input['object'] =>
          input.except('object', 'company_id', 'project_id') }
        if input['data'].present?
          payload['file[data]'] = [input.delete('data'), 'file', 'file_name']
        end
        payload
      else
        input.except('object')
      end
    end,

    format_custom_field_response: lambda do |input|
      input&.each_with_object({}) do |(key, value), hash|
        hash[key] = value['value']
      end || {}
    end,

    project_schema: lambda do
      [
        { name: 'id', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'logo_url' },
        { name: 'name' },
        { name: 'display_name' },
        { name: 'project_number' },
        { name: 'address' },
        { name: 'city' },
        { name: 'state_code' },
        { name: 'country_code' },
        { name: 'zip', label: 'Zip code' },
        { name: 'time_zone' },
        { name: 'tz_name' },
        { name: 'latitude', type: 'number',
          render_input: 'float_conversion' },
        { name: 'longitude', type: 'number',
          render_input: 'float_conversion' },
        { name: 'county' },
        { name: 'parent_job_id', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'description' },
        { name: 'square_feet', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'start_date', type: 'date' },
        { name: 'completion_date', type: 'date' },
        { name: 'total_value', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'store_number', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'accounting_project_number', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'designated_market_area' },
        { name: 'warranty_start_date', type: 'date' },
        { name: 'warranty_end_date', type: 'date' },
        { name: 'active', type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'active', label: 'Active',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } },
        { name: 'flag' },
        { name: 'phone' },
        { name: 'public_notes' },
        { name: 'actual_start_date', type: 'date' },
        { name: 'projected_finish_date', type: 'date' },
        { name: 'created_at', type: 'date_time' },
        { name: 'updated_at', type: 'date_time' },
        { name: 'origin_id' },
        { name: 'origin_data' },
        { name: 'origin_code' },
        { name: 'owners_project_id', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'photo_id', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'inbound_email' },
        { name: 'estimated_start_date', type: 'date' },
        { name: 'estimated_completion_date', type: 'date' },
        { name: 'estimated_value', type: 'number',
          render_input: 'float_conversion' },
        { name: 'persistent_message', type: 'object',
          properties: [
            { name: 'title' },
            { name: 'message' }
          ] },
        { name: 'office', type: 'object',
          properties: [
            { name: 'id', type: 'integer',
              render_input: 'integer_conversion' },
            { name: 'name' }
          ] },
        { name: 'project_bid_type', type: 'object',
          properties: [
            { name: 'id', type: 'integer',
              render_input: 'integer_conversion' },
            { name: 'name' }
          ] },
        { name: 'project_owner_type', type: 'object',
          properties: [
            { name: 'id', type: 'integer',
              render_input: 'integer_conversion' },
            { name: 'name' }
          ] },
        { name: 'project_region', type: 'object',
          properties: [
            { name: 'id', type: 'integer',
              render_input: 'integer_conversion' },
            { name: 'name' }
          ] },
        { name: 'project_stage', type: 'object',
          properties: [
            { name: 'id', type: 'integer',
              render_input: 'integer_conversion' },
            { name: 'name' }
          ] },
        { name: 'project_type', type: 'object',
          properties: [
            { name: 'id', type: 'integer',
              render_input: 'integer_conversion' },
            { name: 'name' }
          ] },
        { name: 'program', type: 'object',
          properties: [
            { name: 'id', type: 'integer',
              render_input: 'integer_conversion' },
            { name: 'name' }
          ] },
        { name: 'departments', type: 'array', of: 'object',
          properties: [
            { name: 'id', type: 'integer',
              render_input: 'integer_conversion' },
            { name: 'name' }
          ] },
        { name: 'company', type: 'object',
          properties: [
            { name: 'id', type: 'integer',
              render_input: 'integer_conversion' },
            { name: 'name' }
          ] }
      ]
    end,

    project_search_schema: lambda do
      [
        { name: 'id', type: 'integer' },
        { name: 'name' },
        { name: 'display_name' },
        { name: 'project_number' },
        { name: 'address' },
        { name: 'city' },
        { name: 'state_code' },
        { name: 'country_code' },
        { name: 'zip', label: 'Zip code' },
        { name: 'latitude', type: 'number' },
        { name: 'longitude', type: 'number' },
        { name: 'stage' },
        { name: 'county' },
        { name: 'start_date', type: 'date' },
        { name: 'completion_date', type: 'date' },
        { name: 'total_value', type: 'integer' },
        { name: 'store_number', type: 'integer' },
        { name: 'accounting_project_number', type: 'integer' },
        { name: 'designated_market_area' },
        { name: 'active', type: 'boolean' },
        { name: 'phone' },
        { name: 'created_at', type: 'date_time' },
        { name: 'updated_at', type: 'date_time' },
        { name: 'origin_id' },
        { name: 'origin_data' },
        { name: 'origin_code' },
        { name: 'owners_project_id', type: 'integer' },
        { name: 'project_region_id', type: 'integer' },
        { name: 'project_bid_type_id', type: 'integer' },
        { name: 'project_owner_type_id', type: 'integer' },
        { name: 'photo_id', type: 'integer' },
        { name: 'estimated_value', type: 'number' },
        { name: 'company', type: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'name' }
          ] }
      ]
    end,

    project_search_query_schema: lambda do
      [
        { name: 'filters', type: 'object',
          properties: [
            { name: 'by_status', label: 'Status', sticky: true,
              type: 'string', control_type: 'select',
              pick_list: [
                %w[All All],
                %w[Active Active],
                %w[Inactive Inactive]
              ],
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'by_status',
                label: 'Status',
                type: :string,
                control_type: 'text',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are All, Active, Inactive.'
              } },
            { name: 'created_at', type: 'object', sticky: true,
              properties: [
                { name: 'from', type: 'date_time', optional: false },
                { name: 'to', type: 'date_time', optional: false }
              ] },
            { name: 'updated_at', type: 'object', sticky: true,
              properties: [
                { name: 'from', type: 'date_time', optional: false },
                { name: 'to', type: 'date_time', optional: false }
              ] },
            { name: 'origin_id', sticky: true },
            { name: 'id', type: 'array', of: 'integer', sticky: true },
            { name: 'synced', type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion', sticky: true,
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'synced', label: 'Synced',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'vendor_id', type: 'integer', sticky: true }
          ] },
        { name: 'serializer_view',
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Compact compact]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'serializer_view',
            label: 'Serializer view',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is compact.'
          } },
        { name: 'sort', sticky: true,
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Name name]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'sort',
            label: 'Sort',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is name.'
          } }
      ]
    end,

    project_trigger_input_schema: lambda do
      [
        { name: 'filters', type: 'object',
          properties: [
            { name: 'by_status', label: 'Status', sticky: true,
              type: 'string', control_type: 'select',
              pick_list: [
                %w[All All],
                %w[Active Active],
                %w[Inactive Inactive]
              ],
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'by_status',
                label: 'Status',
                type: :string,
                control_type: 'text',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are All, Active, Inactive.'
              } },
            { name: 'origin_id' },
            { name: 'synced', type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion', sticky: true,
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'synced', label: 'Synced',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'vendor_id', type: 'integer' }
          ] }
      ]
    end,

    company_user_trigger_input_schema: lambda do
      []
    end,

    project_create_schema: lambda do
      [
        { name: 'name', optional: false },
        { name: 'description', sticky: true },
        { name: 'start_date', type: 'date', sticky: true,
          hint: 'The date that the contract for the project is signed.' },
        { name: 'completion_date', type: 'date', sticky: true,
          hint: 'The date that all parties agree the project meets or must ' \
          'meet "substantial completion".' },
        { name: 'total_value', type: 'integer', sticky: true,
          render_input: 'integer_conversion' },
        { name: 'active', sticky: true,
          type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'active', label: 'Active',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } },
        { name: 'address', sticky: true,
          hint: 'The street address for the Project location' },
        { name: 'city', sticky: true },
        { name: 'state_code', sticky: true,
          hint: 'The code that represents the Project State ' \
          '(ISO-3166 Alpha-2 format)' },
        { name: 'country_code', sticky: true,
          hint: 'The two character code that represents the Country in which ' \
          'the Project is located (ISO-3166 Alpha-2 format)' },
        { name: 'zip', label: 'Zip code', sticky: true },
        { name: 'warranty_start_date', type: 'date' },
        { name: 'warranty_end_date', type: 'date' },
        { name: 'flag', type: 'string', sticky: true,
          control_type: 'select',
          pick_list: [
            %w[Red Red],
            %w[Yellow Yellow],
            %w[Green Green]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'flag',
            label: 'Flag',
            type: :string,
            control_type: 'text',
            optional: true,
            hint: 'Allowed values are Red, Yellow, Green.',
            toggle_hint: 'Use custom value'
          } },
        { name: 'image_id', render_input: 'integer_conversion' },
        { name: 'office_id', label: 'Office',
          type: 'string',
          control_type: 'select',
          pick_list: 'office_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'office_id',
            label: 'Office ID',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value'
          } },
        { name: 'phone' },
        { name: 'project_number' },
        { name: 'public_notes' },
        { name: 'project_stage_id', label: 'Project stage',
          type: 'string',
          control_type: 'select',
          pick_list: 'project_stage_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_stage_id',
            label: 'Project stage ID',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value'
          } },
        { name: 'square_feet', render_input: 'integer_conversion' },
        { name: 'time_zone' },
        { name: 'parent_job_id', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'program_id', label: 'Program',
          type: 'string',
          control_type: 'select',
          pick_list: 'program_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'program_id',
            label: 'Program ID',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value'
          } },
        { name: 'project_bid_type_id', label: 'Project bid type',
          type: 'string',
          control_type: 'select',
          pick_list: 'project_bid_type_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_bid_type_id',
            label: 'Project bid type ID',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value'
          } },
        { name: 'project_type_id', label: 'Project type',
          type: 'string',
          control_type: 'select',
          pick_list: 'project_type_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_type_id',
            label: 'Project type ID',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value'
          } },
        { name: 'project_owner_type_id', label: 'Project owner type',
          type: 'string',
          control_type: 'select',
          pick_list: 'project_owner_type_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_owner_type_id',
            label: 'Project owner type ID',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value'
          } },
        { name: 'project_region_id', label: 'Project region',
          type: 'string',
          control_type: 'select',
          pick_list: 'project_region_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_region_id',
            label: 'Project region ID',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value'
          } },
        { name: 'project_template_id', label: 'Project template',
          type: 'string',
          control_type: 'select',
          pick_list: 'project_template_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_template_id',
            label: 'Project template ID',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value'
          } },
        { name: 'origin_id' },
        { name: 'origin_data' },
        { name: 'origin_code' },
        { name: 'store_number', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'accounting_project_number', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'designated_market_area' },
        { name: 'estimated_start_date', type: 'date' },
        { name: 'estimated_completion_date', type: 'date' },
        { name: 'estimated_value', type: 'number',
          render_input: 'float_conversion' },
        { name: 'departments', type: 'array', of: 'integer' }
      ]
    end,

    project_update_schema: lambda do
      call('project_create_schema')
    end,

    company_search_schema: lambda do
      [
        { name: 'id', type: 'integer' },
        { name: 'name' },
        { name: 'is_active', type: 'boolean' }
      ]
    end,

    company_search_query_schema: lambda do
      []
    end,

    company_vendor_schema: lambda do
      [
        { name: 'id', type: 'integer' },
        { name: 'name' },
        { name: 'abbreviated_name' },
        { name: 'address' },
        { name: 'authorized_bidder', type: 'boolean' },
        { name: 'business_phone' },
        { name: 'city' },
        { name: 'contact_count', type: 'integer' },
        { name: 'company' },
        { name: 'country_code' },
        { name: 'created_at', type: 'date_time' },
        { name: 'email_address' },
        { name: 'fax_number' },
        { name: 'is_active', type: 'boolean' },
        { name: 'labor_union' },
        { name: 'license_number' },
        { name: 'logo' },
        { name: 'mobile_phone' },
        { name: 'non_union_prevailing_wage', type: 'boolean' },
        { name: 'notes' },
        { name: 'origin_data' },
        { name: 'origin_id' },
        { name: 'origin_code' },
        { name: 'prequalified', type: 'boolean' },
        { name: 'state_code' },
        { name: 'synced_to_erp', type: 'boolean' },
        { name: 'trade_name' },
        { name: 'union_member', type: 'boolean' },
        { name: 'updated_at', type: 'date_time' },
        { name: 'website' },
        { name: 'zip', label: 'Zip code' },
        { name: 'business_register', type: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'type' },
            { name: 'identifier' },
            { name: 'verified_at', type: 'date_time' },
            { name: 'verification_status' }
          ] },
        { name: 'vendor_group', type: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'name' }
          ] },
        { name: 'primary_contact', type: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'first_name' },
            { name: 'last_name' },
            { name: 'business_phone' },
            { name: 'business_phone_extension', type: 'integer' },
            { name: 'fax_number' },
            { name: 'mobile_phone' },
            { name: 'email_address' },
            { name: 'created_at', type: 'date_time' },
            { name: 'updated_at', type: 'date_time' }
          ] },
        { name: 'attachments', type: 'array', of: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'url' },
            { name: 'filename' }
          ] },
        { name: 'project_ids', type: 'array', of: 'integer' },
        { name: 'standard_cost_codes', type: 'array', of: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'standard_cost_code_list_id', type: 'integer' },
            { name: 'parent_id', type: 'integer' },
            { name: 'code' },
            { name: 'full_code' },
            { name: 'name' },
            { name: 'origin_data' },
            { name: 'origin_id' }
          ] },
        { name: 'children_count', type: 'integer' },
        { name: 'legal_name' },
        { name: 'parent', type: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'name' }
          ] },
        { name: 'trades', type: 'array', of: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'name' },
            { name: 'active', type: 'boolean' },
            { name: 'updated_at', type: 'date_time' }
          ] },
        { name: 'bidding_distribution', type: 'array', of: 'object',
          properties: [
            { name: 'login' },
            { name: 'id', type: 'integer' },
            { name: 'name' }
          ] },
        { name: 'bidding', type: 'object',
          properties: [
            { name: 'affirmative_action', type: 'boolean' },
            { name: 'small_business', type: 'boolean' },
            { name: 'african_american_business', type: 'boolean' },
            { name: 'hispanic_business', type: 'boolean' },
            { name: 'womens_business', type: 'boolean' },
            { name: 'historically_underutilized_business', type: 'boolean' },
            { name: 'sdvo_business', type: 'boolean' },
            { name: 'certified_business_enterprise', type: 'boolean' },
            { name: 'asian_american_business', type: 'boolean' },
            { name: 'native_american_business', type: 'boolean' },
            { name: 'disadvantaged_business', type: 'boolean' },
            { name: 'minority_business_enterprise', type: 'boolean' },
            { name: 'eight_a_business', type: 'boolean' }
          ] }
      ]
    end,

    company_vendor_inactive_search_schema: lambda do
      call('company_vendor_schema')
    end,

    company_vendor_inactive_search_query_schema: lambda do
      [
        { name: 'view',
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Compact compact],
            %w[Normal normal],
            %w[ERP erp],
            %w[Extended extended]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'view',
            label: 'View',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is compact, normal, erp, extended.'
          } },
        { name: 'sort', sticky: true,
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Name name]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'sort',
            label: 'Sort',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is name, main_office_name.'
          } }
      ]
    end,

    company_vendor_search_schema: lambda do
      call('company_vendor_schema')
    end,

    company_vendor_search_query_schema: lambda do
      [
        { name: 'filters', type: 'object',
          properties: [
            { name: 'search', sticky: true,
              hint: 'The search string matches the vendor name, keywords, ' \
              'origin_code, or ABN/EIN number' },
            { name: 'created_at', type: 'object', sticky: true,
              properties: [
                { name: 'from', type: 'date_time', optional: false },
                { name: 'to', type: 'date_time', optional: false }
              ] },
            { name: 'updated_at', type: 'object', sticky: true,
              properties: [
                { name: 'from', type: 'date_time', optional: false },
                { name: 'to', type: 'date_time', optional: false }
              ] },
            { name: 'id', type: 'array', of: 'integer', sticky: true },
            { name: 'origin_id' },
            { name: 'parent_id', type: 'array', of: 'integer', sticky: true },
            { name: 'standard_cost_code_id', type: 'array', of: 'integer' },
            { name: 'trade_id', type: 'array', of: 'integer' }
          ] },
        { name: 'view',
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Compact compact],
            %w[Normal normal],
            %w[ERP erp],
            %w[Extended extended]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'view',
            label: 'View',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is compact, normal, erp, extended.'
          } },
        { name: 'sort', sticky: true,
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Name name],
            %w[Main\ office\ name main_office_name]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'sort',
            label: 'Sort',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is name, main_office_name.'
          } }
      ]
    end,

    company_vendor_create_schema: lambda do
      [
        { name: 'name', optional: false },
        { name: 'email_address', sticky: true },
        { name: 'address', sticky: true,
          hint: 'The street address' },
        { name: 'city' },
        { name: 'country_code', sticky: true,
          hint: 'The two character code that represents the Country ' \
          '(ISO-3166 Alpha-2 format)' },
        { name: 'state_code', sticky: true,
          hint: 'The two character code that represents the State ' \
          '(ISO-3166 Alpha-2 format)' },
        { name: 'zip', label: 'Zip code' },
        { name: 'business_phone' },
        { name: 'mobile_phone' },
        { name: 'fax_number' },
        { name: 'is_active', sticky: true,
          type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'is_active', label: 'Is active',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } },
        { name: 'authorized_bidder',
          type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'authorized_bidder',
            label: 'Authorized bidder',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } },
        { name: 'prequalified',
          type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'prequalified', label: 'Prequalified',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } },
        { name: 'labor_union' },
        { name: 'license_number' },
        { name: 'website' },
        { name: 'union_member',
          type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'union_member', label: 'Union member',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } },
        { name: 'non_union_prevailing_wage',
          type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'non_union_prevailing_wage',
            label: 'Non union prevailing wage',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } },
        { name: 'abbreviated_name' },
        { name: 'notes' },
        { name: 'vendor_group_id', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'parent_id', label: 'Parent vendor',
          type: 'string',
          control_type: 'select',
          pick_list: 'company_vendor_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'parent_id',
            label: 'Parent vendor ID',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the parent vender.'
          } },
        { name: 'primary_contact_id', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'origin_id' },
        { name: 'origin_data' },
        { name: 'origin_code' },
        { name: 'trade_ids', type: 'array', of: 'integer' },
        { name: 'bidding_distribution_ids', type: 'array', of: 'integer' },
        { name: 'standard_cost_code_ids', type: 'array', of: 'integer' },
        { name: 'trade_name' },
        { name: 'bidding', type: 'object',
          properties: [
            { name: 'affirmative_action',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'affirmative_action',
                label: 'Affirmative action',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'small_business',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'small_business', label: 'Small business',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'african_american_business',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'african_american_business',
                label: 'African american business',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'hispanic_business',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'hispanic_business',
                label: 'Hispanic business',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'womens_business',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'womens_business', label: 'Womens business',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'historically_underutilized_business',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'historically_underutilized_business',
                label: 'Historically underutilized business',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'sdvo_business',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'sdvo_business', label: 'Sdvo business',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'certified_business_enterprise',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'certified_business_enterprise',
                label: 'Certified business enterprise',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'asian_american_business',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'asian_american_business',
                label: 'Asian american business',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'native_american_business',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'native_american_business',
                label: 'Native american business',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'disadvantaged_business',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'disadvantaged_business',
                label: 'Disadvantaged business',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'minority_business_enterprise',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'minority_business_enterprise',
                label: 'Minority business enterprise',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'eight_a_business',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'eight_a_business', label: 'Eight a business',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } }
          ] }
      ]
    end,

    company_vendor_update_schema: lambda do
      [{ name: 'name', sticky: true }].
        concat(call('company_vendor_create_schema').ignored('name'))
    end,

    project_vendor_schema: lambda do
      call('company_vendor_schema').
        ignored('project_ids', 'standard_cost_codes', 'children_count',
                'legal_name', 'parent', 'trades',
                'bidding_distribution', 'bidding')
    end,

    project_vendor_search_schema: lambda do
      call('project_vendor_schema')
    end,

    project_vendor_search_query_schema: lambda do
      [
        { name: 'project_id', label: 'Project',
          type: 'string', optional: false,
          control_type: 'select',
          pick_list: 'project_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_id', label: 'Project ID',
            type: :string,
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the project.'
          } },
        { name: 'filters', type: 'object',
          properties: [
            { name: 'search', sticky: true,
              hint: 'The search string matches the vendor name, keywords, ' \
              'origin_code, or ABN/EIN number' },
            { name: 'id', type: 'array', of: 'integer', sticky: true },
            { name: 'parent_id', type: 'array', of: 'integer', sticky: true },
            { name: 'standard_cost_code_id', type: 'array', of: 'integer' },
            { name: 'trade_id', type: 'array', of: 'integer' }
          ] },
        { name: 'view',
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Compact compact],
            %w[Normal normal],
            %w[ERP erp],
            %w[Extended extended]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'view',
            label: 'View',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is compact, normal, erp, extended.'
          } },
        { name: 'sort', sticky: true,
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Name name],
            %w[Main\ office\ name main_office_name]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'sort',
            label: 'Sort',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is name, main_office_name.'
          } }
      ]
    end,

    project_vendor_inactive_search_schema: lambda do
      call('project_vendor_schema')
    end,

    project_vendor_inactive_search_query_schema: lambda do
      [
        { name: 'project_id', label: 'Project',
          type: 'string', optional: false,
          control_type: 'select',
          pick_list: 'project_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_id', label: 'Project ID',
            type: :string,
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the project.'
          } },
        { name: 'filters', type: 'object',
          properties: [
            { name: 'search', sticky: true,
              hint: 'The search string matches the vendor name, keywords, ' \
              'origin_code, or ABN/EIN number' },
            { name: 'id', type: 'array', of: 'integer', sticky: true },
            { name: 'parent_id', type: 'array', of: 'integer', sticky: true },
            { name: 'standard_cost_code_id', type: 'array', of: 'integer' },
            { name: 'trade_id', type: 'array', of: 'integer' }
          ] },
        { name: 'view',
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Compact compact],
            %w[Normal normal],
            %w[ERP erp],
            %w[Extended extended]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'view',
            label: 'View',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is compact, normal, erp, extended.'
          } },
        { name: 'sort', sticky: true,
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Name name]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'sort',
            label: 'Sort',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is name, main_office_name.'
          } }
      ]
    end,

    project_vendor_create_schema: lambda do
      call('company_vendor_create_schema').
        ignored('vendor_group_id', 'trade_ids', 'bidding_distribution_ids',
                'standard_cost_code_ids', 'bidding', 'parent_id').
        concat(
          [
            { name: 'project_id', label: 'Project',
              type: 'string', optional: false,
              control_type: 'select',
              extends_schema: true,
              pick_list: 'project_list',
              pick_list_params: { company_id: 'company_id' },
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'project_id', label: 'Project ID',
                type: :string,
                control_type: 'text',
                extends_schema: true, change_on_blur: true,
                optional: false,
                toggle_hint: 'Use custom value',
                hint: 'Provide ID of the project.'
              } },
            { name: 'parent_id', label: 'Parent vendor',
              type: 'string',
              control_type: 'select',
              pick_list: 'project_vendor_list',
              pick_list_params: { project_id: 'project_id' },
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'parent_id',
                label: 'Parent vendor ID',
                type: :string,
                control_type: 'text',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Provide ID of the parent vender.'
              } }
          ]
        )
    end,

    project_vendor_update_schema: lambda do
      [{ name: 'name', sticky: true }].
        concat(call('project_vendor_create_schema').ignored('name'))
    end,

    project_person_schema: lambda do
      [
        { name: 'contact', type: 'object',
          properties: [{ name: 'is_active', type: 'boolean' }] },
        { name: 'employee_id' },
        { name: 'first_name' },
        { name: 'id', type: 'integer' },
        { name: 'is_employee', type: 'boolean' },
        { name: 'last_name' },
        { name: 'user_id', type: 'integer' },
        { name: 'work_classification_id', type: 'integer' }
      ]
    end,

    project_person_search_schema: lambda do
      call('project_person_schema')
    end,

    project_person_search_query_schema: lambda do
      [
        { name: 'project_id', label: 'Project',
          type: 'string', optional: false,
          control_type: 'select',
          pick_list: 'project_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_id', label: 'Project ID',
            type: :string,
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the project.'
          } },
        { name: 'filters', type: 'object',
          properties: [
            { name: 'search', sticky: true,
              hint: 'Returns item(s) matching the specified search string.' },
            { name: 'is_employee',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'is_employee',
                label: 'Is employee',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'reference_users_only',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'reference_users_only',
                label: 'Reference users only',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'include_company_people',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'include_company_people',
                label: 'Include company people',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } }
          ] }
      ]
    end,

    project_person_inactive_search_schema: lambda do
      call('project_person_schema')
    end,

    project_person_inactive_search_query_schema: lambda do
      [
        { name: 'project_id', label: 'Project',
          type: 'string', optional: false,
          control_type: 'select',
          pick_list: 'project_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_id', label: 'Project ID',
            type: :string,
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the project.'
          } },
        { name: 'filters', type: 'object',
          properties: [
            { name: 'search', sticky: true,
              hint: 'Returns item(s) matching the specified search string.' },
            { name: 'is_employee',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'is_employee',
                label: 'Is employee',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'reference_users_only',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'reference_users_only',
                label: 'Reference users only',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'include_company_people',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'include_company_people',
                label: 'Include company people',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } }
          ] }
      ]
    end,

    project_person_create_schema: lambda do
      [
        { name: 'project_id', label: 'Project',
          type: 'string', optional: false,
          control_type: 'select',
          pick_list: 'project_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_id', label: 'Project ID',
            type: :string,
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the project.'
          } },
        { name: 'first_name', sticky: true },
        { name: 'last_name', optional: false },
        { name: 'employee_id', sticky: true },
        { name: 'is_employee', sticky: true,
          type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'is_employee', label: 'Is employee',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } }
      ]
    end,

    project_person_update_schema: lambda do
      call('project_person_create_schema')
    end,

    company_person_schema: lambda do
      call('project_person_schema')
    end,

    company_person_search_schema: lambda do
      call('project_person_schema')
    end,

    company_person_search_query_schema: lambda do
      [
        { name: 'filters', type: 'object',
          properties: [
            { name: 'search', sticky: true,
              hint: 'Returns item(s) matching the specified search string.' },
            { name: 'is_employee',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'is_employee',
                label: 'Is employee',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'reference_users_only',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'reference_users_only',
                label: 'Reference users only',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'include_company_people',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'include_company_people',
                label: 'Include company people',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } }
          ] }
      ]
    end,

    company_person_inactive_search_schema: lambda do
      call('project_person_schema')
    end,

    company_person_inactive_search_query_schema: lambda do
      [
        { name: 'filters', type: 'object',
          properties: [
            { name: 'search', sticky: true,
              hint: 'Returns item(s) matching the specified search string.' },
            { name: 'is_employee',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'is_employee',
                label: 'Is employee',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'reference_users_only',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'reference_users_only',
                label: 'Reference users only',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'include_company_people',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'include_company_people',
                label: 'Include company people',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } }
          ] }
      ]
    end,

    company_person_update_schema: lambda do
      call('project_person_update_schema').ignored('project_id')
    end,

    company_user_schema: lambda do
      [
        { name: 'id', type: 'integer' },
        { name: 'name' },
        { name: 'first_name' },
        { name: 'last_name' },
        { name: 'initials' },
        { name: 'email_address' },
        { name: 'email_signature' },
        { name: 'address' },
        { name: 'city' },
        { name: 'state_code' },
        { name: 'country_code' },
        { name: 'zip', label: 'Zip code' },
        { name: 'employee_id' },
        { name: 'job_title' },
        { name: 'mobile_phone' },
        { name: 'business_phone' },
        { name: 'business_phone_extension' },
        { name: 'fax_number' },
        { name: 'is_active', type: 'boolean' },
        { name: 'is_employee', type: 'boolean' },
        { name: 'notes' },
        { name: 'avatar' },
        { name: 'last_login_at', type: 'date_time' },
        { name: 'erp_integrated_accountant', type: 'boolean',
          label: 'ERP integrated accountant' },
        { name: 'welcome_email_sent_at', type: 'date_time' },
        { name: 'origin_id' },
        { name: 'origin_data' },
        { name: 'created_at', type: 'date_time' },
        { name: 'updated_at', type: 'date_time' },
        { name: 'vendor', type: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'name' }
          ] },
        { name: 'work_classification_id', type: 'integer' },
        { name: 'default_permission_template_id', type: 'integer' },
        { name: 'permission_template', type: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'name' },
            { name: 'project_specific', type: 'boolean' },
            { name: 'type' }
          ] },
        { name: 'company_permission_template_id', type: 'integer' }
      ]
    end,

    company_user_search_schema: lambda do
      call('company_user_schema')
    end,

    company_user_search_query_schema: lambda do
      [
        { name: 'filters', type: 'object',
          properties: [
            { name: 'search', sticky: true,
              hint: 'The search string matches the vendor name, keywords, ' \
              'origin_code, or ABN/EIN number' },
            { name: 'active',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              hint: "If true, returns item(s) with a status of 'active'.",
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'active',
                label: 'Active',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'created_at', type: 'object', sticky: true,
              properties: [
                { name: 'from', type: 'date_time', optional: false },
                { name: 'to', type: 'date_time', optional: false }
              ] },
            { name: 'updated_at', type: 'object', sticky: true,
              properties: [
                { name: 'from', type: 'date_time', optional: false },
                { name: 'to', type: 'date_time', optional: false }
              ] },
            { name: 'origin_id' },
            { name: 'vendor_id', type: 'array', of: 'integer', sticky: true },
            { name: 'trade_id', type: 'array', of: 'integer' }
          ] },
        { name: 'sort', sticky: true,
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Name name],
            %w[Vendor\ name vendor_name],
            %w[Full\ name full_name],
            %w[Permission\ template permission_template]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'sort',
            label: 'Sort',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is name, , vendor_name, full_name, ' \
            'permission_template.'
          } }
      ]
    end,

    company_user_inactive_search_schema: lambda do
      call('company_user_schema')
    end,

    company_user_inactive_search_query_schema: lambda do
      [
        { name: 'sort', sticky: true,
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Name name]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'sort',
            label: 'Sort',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is name, , vendor_name, full_name, ' \
            'permission_template.'
          } }
      ]
    end,

    company_user_create_schema: lambda do
      [
        { name: 'first_name', sticky: true },
        { name: 'last_name', optional: false },
        { name: 'initials', sticky: true },
        { name: 'email_address', optional: false },
        { name: 'email_signature', sticky: true },
        { name: 'address', sticky: true,
          hint: 'The street address' },
        { name: 'city', sticky: true },
        { name: 'state_code', sticky: true,
          hint: 'The two character code that represents the State ' \
          '(ISO-3166 Alpha-2 format)' },
        { name: 'country_code', sticky: true,
          hint: 'The two character code that represents the Country ' \
          '(ISO-3166 Alpha-2 format)' },
        { name: 'zip', label: 'Zip code', sticky: true },
        { name: 'mobile_phone', sticky: true },
        { name: 'business_phone' },
        { name: 'business_phone_extension', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'fax_number' },
        { name: 'employee_id' },
        { name: 'job_title' },
        { name: 'is_active', sticky: true,
          type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'is_active', label: 'Is active',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } },
        { name: 'is_employee', sticky: true,
          type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'is_employee', label: 'Is employee',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true, toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } },
        { name: 'notes' },
        { name: 'origin_id' },
        { name: 'origin_data' },
        { name: 'default_permission_template_id', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'company_permission_template_id', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'work_classification_id', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'vendor_id', type: 'integer',
          render_input: 'integer_conversion' },
        { name: 'avatar', hint: 'The file content of avatar' }
      ]
    end,

    company_user_update_schema: lambda do
      call('company_user_create_schema')
    end,

    project_user_schema: lambda do
      call('company_user_schema').ignored('company_permission_template_id')
    end,

    project_user_search_schema: lambda do
      call('project_user_schema')
    end,

    project_user_search_query_schema: lambda do
      [
        { name: 'project_id', label: 'Project',
          type: 'string', optional: false,
          control_type: 'select',
          pick_list: 'project_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_id', label: 'Project ID',
            type: :string,
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the project.'
          } },
        { name: 'filters', type: 'object',
          properties: [
            { name: 'search', sticky: true,
              hint: 'The search string matches the vendor name, keywords, ' \
              'origin_code, or ABN/EIN number' },
            { name: 'active',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              hint: "If true, returns item(s) with a status of 'active'.",
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'active',
                label: 'Active',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'employee',
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              hint: "If true, returns item(s) with a status of 'active'.",
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'employee',
                label: 'Employee',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'created_at', type: 'object', sticky: true,
              properties: [
                { name: 'from', type: 'date_time', optional: false },
                { name: 'to', type: 'date_time', optional: false }
              ] },
            { name: 'updated_at', type: 'object', sticky: true,
              properties: [
                { name: 'from', type: 'date_time', optional: false },
                { name: 'to', type: 'date_time', optional: false }
              ] },
            { name: 'origin_id' },
            { name: 'permission_template', label: 'Permission template ID',
              type: 'integer', render_input: 'integer_conversion' },
            { name: 'vendor_id', type: 'array', of: 'integer', sticky: true },
            { name: 'trade_id', type: 'array', of: 'integer' }
          ] },
        { name: 'sort', sticky: true,
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Name name],
            %w[Vendor\ name vendor_name],
            %w[Permission\ template permission_template]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'sort',
            label: 'Sort',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is name, vendor_name, permission_template.'
          } }
      ]
    end,

    project_user_inactive_search_schema: lambda do
      call('project_user_schema')
    end,

    project_user_inactive_search_query_schema: lambda do
      [
        { name: 'project_id', label: 'Project',
          type: 'string', optional: false,
          control_type: 'select',
          pick_list: 'project_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_id', label: 'Project ID',
            type: :string,
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the project.'
          } },
        { name: 'sort', sticky: true,
          type: 'string', control_type: 'select',
          pick_list: [
            %w[Name name],
            %w[Vendor\ name vendor_name],
            %w[Permission\ template permission_template]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'sort',
            label: 'Sort',
            type: :string,
            control_type: 'text',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed value is name, vendor_name, permission_template.'
          } }
      ]
    end,

    project_user_create_schema: lambda do
      call('company_user_create_schema').
        ignored('origin_id', 'origin_data', 'default_permission_template_id',
                'company_permission_template_id', 'work_classification_id').
        concat(
          [
            { name: 'project_id', label: 'Project',
              type: 'string', optional: false,
              control_type: 'select',
              pick_list: 'project_list',
              pick_list_params: { company_id: 'company_id' },
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'project_id', label: 'Project ID',
                type: :string,
                control_type: 'text',
                optional: false,
                toggle_hint: 'Use custom value',
                hint: 'Provide ID of the project.'
              } },
            { name: 'permission_template_id', type: 'integer',
              render_input: 'integer_conversion' }
          ]
        )
    end,

    project_user_update_schema: lambda do
      call('project_user_create_schema')
    end,

    project_role_search_query_schema: lambda do
      [
        { name: 'project_id', label: 'Project',
          type: 'string', optional: false,
          control_type: 'select',
          pick_list: 'project_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_id', label: 'Project ID',
            type: :string,
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the project.'
          } },
        { name: 'filters', type: 'object',
          properties: [
            { name: 'created_at', type: 'object', sticky: true,
              properties: [
                { name: 'from', type: 'date_time', optional: false },
                { name: 'to', type: 'date_time', optional: false }
              ] }
          ] },
        { name: 'page', type: 'integer' },
        { name: 'per_page', type: 'integer',
          hint: 'default: 20, max: 100' }
      ]
    end,

    project_role_search_schema: lambda do
      call('project_role_schema')
    end,

    company_role_search_schema: lambda do
      call('project_role_schema').only('id', 'name')
    end,

    project_role_schema: lambda do
      [
        { name: 'id', type: 'integer' },
        { name: 'name' },
        { name: 'role' },
        { name: 'user_id', type: 'integer' },
        { name: 'contact_id', type: 'integer' },
        { name: 'created_at', type: 'date_time' },
        { name: 'is_active', type: 'boolean' }
      ]
    end,

    user_project_role_schema: lambda do
      [
        { name: 'project_id', label: 'Project',
          type: 'string', optional: false,
          control_type: 'select',
          pick_list: 'project_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_id', label: 'Project ID',
            type: :string,
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the project.'
          } },
        { name: 'id', label: 'Role',
          type: 'string', optional: false,
          control_type: 'select',
          pick_list: 'company_role_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'id', label: 'Company Role ID',
            type: :string,
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the company role.'
          } },
        { name: 'user_ids', label: 'User IDs', optional: false,
          type: 'array', of: 'integer',
          hint: 'User IDs to associate with the Project Role' }
      ]
    end,

    folder_create_schema: lambda do
      [
        { name: 'project_id', label: 'Project',
          type: 'string', optional: false,
          control_type: 'select',
          pick_list: 'project_list',
          pick_list_params: { company_id: 'company_id' },
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project_id', label: 'Project ID',
            type: :string,
            control_type: 'text',
            optional: false,
            toggle_hint: 'Use custom value',
            hint: 'Provide ID of the project.'
          } },
        { name: 'parent_id', type: 'integer', sticky: true,
          render_input: 'integer_conversion' },
        { name: 'name', optional: false },
        { name: 'is_tracked',
          type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion', sticky: true,
          hint: 'Status if a folder/file should be tracked.',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'is_tracked',
            label: 'Is tracked',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } },
        { name: 'explicit_permissions',
          type: 'boolean', control_type: 'checkbox',
          render_input: 'boolean_conversion', sticky: true,
          hint: 'Set folder/file to private.',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'explicit_permissions',
            label: 'Explicit permissions',
            type: 'string', control_type: 'text',
            render_input: 'boolean_conversion',
            optional: true,
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are true, false'
          } }
      ]
    end,

    folder_update_schema: lambda do
      [{ name: 'name', sticky: true }].
        concat(call('folder_create_schema').ignored('name'))
    end,

    folder_schema: lambda do
      [
        { name: 'id', type: 'integer' },
        { name: 'name' },
        { name: 'parent_id', type: 'integer' },
        { name: 'private', type: 'boolean' },
        { name: 'updated_at', type: 'date_time' },
        { name: 'is_tracked', type: 'boolean' },
        { name: 'name_with_path' },
        { name: 'folders', type: 'array', of: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'name' },
            { name: 'parent_id', type: 'integer' },
            { name: 'private', type: 'boolean' },
            { name: 'updated_at', type: 'date_time' },
            { name: 'is_tracked', type: 'boolean' },
            { name: 'name_with_path' },
            { name: 'folders', type: 'array', of: 'object', properties: [] },
            { name: 'files', type: 'array', of: 'object', properties: [] },
            { name: 'read_only', type: 'boolean' },
            { name: 'is_deleted', type: 'boolean' },
            { name: 'is_recycle_bin', type: 'boolean' },
            { name: 'has_children', type: 'boolean' },
            { name: 'has_children_files', type: 'boolean' },
            { name: 'has_children_folders', type: 'boolean' }
          ] },
        { name: 'files', type: 'array', of: 'object',
          properties: call('file_schema') },
        { name: 'read_only', type: 'boolean' },
        { name: 'is_deleted', type: 'boolean' },
        { name: 'is_recycle_bin', type: 'boolean' },
        { name: 'has_children', type: 'boolean' },
        { name: 'has_children_files', type: 'boolean' },
        { name: 'has_children_folders', type: 'boolean' }
      ]
    end,

    file_create_schema: lambda do
      call('folder_create_schema').concat(
        [
          { name: 'description', sticky: true },
          { name: 'data', sticky: true,
            hint: 'File to use as file data. You should not use both file ' \
            'and upload_uuid fields' },
          { name: 'upload_uuid', sticky: true,
            hint: 'UUID referencing a previously completed Upload.' },
          { name: 'unique_name',
            type: 'boolean', control_type: 'checkbox',
            render_input: 'boolean_conversion', sticky: true,
            hint: 'If true, Toggles automatic renaming if the file ' \
            'name is already taken in a folder',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'unique_name',
              label: 'Unique name',
              type: 'string', control_type: 'text',
              render_input: 'boolean_conversion',
              optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are true, false'
            } }
        ]
      )
    end,

    file_update_schema: lambda do
      call('file_create_schema')
    end,

    file_schema: lambda do
      [
        { name: 'id', type: 'integer' },
        { name: 'name' },
        { name: 'parent_id', type: 'integer' },
        { name: 'size', type: 'integer' },
        { name: 'description' },
        { name: 'updated_at', type: 'date_time' },
        { name: 'created_at', type: 'date_time' },
        { name: 'checked_out_until', type: 'date_time' },
        { name: 'name_with_path' },
        { name: 'private', type: 'boolean' },
        { name: 'is_tracked', type: 'boolean' },
        { name: 'checked_out_by', type: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'login' },
            { name: 'name' }
          ] },
        { name: 'file_type' },
        { name: 'file_versions', type: 'array', of: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'notes' },
            { name: 'url' },
            { name: 'size', type: 'integer' },
            { name: 'created_at', type: 'date_time' },
            { name: 'number', type: 'integer' },
            { name: 'created_by', type: 'object',
              properties: [
                { name: 'id', type: 'integer' },
                { name: 'login' },
                { name: 'name' }
              ] },
            { name: 'prostore_file', type: 'object',
              properties: [
                { name: 'id', type: 'integer' },
                { name: 'name' },
                { name: 'url' },
                { name: 'filename' }
              ] },
            { name: 'file_id', type: 'integer' }
          ] },
        { name: 'legacy_id', type: 'integer' },
        { name: 'is_deleted', type: 'boolean' }
      ]
    end,
    
    
    # -----------------------------
    # Check if object (Hash)
    # -----------------------------
    is_object: lambda do |value|
      value.is_a?(Hash)
    end,

    deep_replace: lambda do |value, old_name, new_name|

  if value.is_a?(String)

    # 1. Replace normal string
    updated = value.include?(old_name) ? value.gsub(old_name, new_name) : value

    # 2. Try parsing if string is JSON
    begin
      parsed = parse_json(updated)

      # If parsing works → recursively fix inside
      replaced = call(:deep_replace, parsed, old_name, new_name)

      # Convert back to string
      replaced.to_json

    rescue
      # Not JSON → return normal string
      updated
    end

  elsif value.is_a?(Array)
    value.map do |item|
      call(:deep_replace, item, old_name, new_name)
    end

  elsif value.is_a?(Hash)
    result = {}
    value.each do |key, val|
      result[key] = call(:deep_replace, val, old_name, new_name)
    end
    result

  else
    value
  end
end
  },

  object_definitions: {
    custom_action_input: {
      fields: lambda do |connection, config_fields|
        verb = config_fields['verb']
        input_schema = parse_json(config_fields.dig('input', 'schema') || '[]')
        data_props =
          input_schema.map do |field|
            if config_fields['request_type'] == 'multipart' &&
               field['binary_content'] == 'true'
              field['type'] = 'object'
              field['properties'] = [
                { name: 'file_content', optional: false },
                {
                  name: 'content_type',
                  default: 'text/plain',
                  sticky: true
                },
                { name: 'original_filename', sticky: true }
              ]
            end
            field
          end
        data_props = call('make_schema_builder_fields_sticky', data_props)
        input_data =
          if input_schema.present?
            if input_schema.dig(0, 'type') == 'array' &&
               input_schema.dig(0, 'details', 'fake_array')
              {
                name: 'data',
                type: 'array',
                of: 'object',
                properties: data_props.dig(0, 'properties')
              }
            else
              { name: 'data', type: 'object', properties: data_props }
            end
          end

        [
          {
            name: 'path',
            hint: 'Base URI is <b>' \
            "https://#{connection['environment']}/rest/v1.0/" \
            '</b> - path will be appended to this URI. Use absolute URI to ' \
            'override this base URI.',
            optional: false
          },
          if %w[post put patch].include?(verb)
            {
              name: 'request_type',
              default: 'json',
              sticky: true,
              extends_schema: true,
              control_type: 'select',
              pick_list: [
                ['JSON request body', 'json'],
                ['URL encoded form', 'url_encoded_form'],
                ['Mutipart form', 'multipart'],
                ['Raw request body', 'raw']
              ]
            }
          end,
          {
            name: 'response_type',
            default: 'json',
            sticky: false,
            extends_schema: true,
            control_type: 'select',
            pick_list: [['JSON response', 'json'], ['Raw response', 'raw']]
          },
          if %w[get options delete].include?(verb)
            {
              name: 'input',
              label: 'Request URL parameters',
              sticky: true,
              add_field_label: 'Add URL parameter',
              control_type: 'form-schema-builder',
              type: 'object',
              properties: [
                {
                  name: 'schema',
                  sticky: input_schema.blank?,
                  extends_schema: true
                },
                input_data
              ].compact
            }
          else
            {
              name: 'input',
              label: 'Request body parameters',
              sticky: true,
              type: 'object',
              properties:
                if config_fields['request_type'] == 'raw'
                  [{
                    name: 'data',
                    sticky: true,
                    control_type: 'text-area',
                    type: 'string'
                  }]
                else
                  [
                    {
                      name: 'schema',
                      sticky: input_schema.blank?,
                      extends_schema: true,
                      schema_neutral: true,
                      control_type: 'schema-designer',
                      sample_data_type: 'json_input',
                      custom_properties:
                        if config_fields['request_type'] == 'multipart'
                          [{
                            name: 'binary_content',
                            label: 'File attachment',
                            default: false,
                            optional: true,
                            sticky: true,
                            render_input: 'boolean_conversion',
                            parse_output: 'boolean_conversion',
                            control_type: 'checkbox',
                            type: 'boolean'
                          }]
                        end
                    },
                    input_data
                  ].compact
                end
            }
          end,
          {
            name: 'request_headers',
            sticky: false,
            extends_schema: true,
            control_type: 'key_value',
            empty_list_title: 'Does this HTTP request require headers?',
            empty_list_text: 'Refer to the API documentation and add ' \
            'required headers to this HTTP request',
            item_label: 'Header',
            type: 'array',
            of: 'object',
            properties: [{ name: 'key' }, { name: 'value' }]
          },
          unless config_fields['response_type'] == 'raw'
            {
              name: 'output',
              label: 'Response body',
              sticky: true,
              extends_schema: true,
              schema_neutral: true,
              control_type: 'schema-designer',
              sample_data_type: 'json_input'
            }
          end,
          {
            name: 'response_headers',
            sticky: false,
            extends_schema: true,
            schema_neutral: true,
            control_type: 'schema-designer',
            sample_data_type: 'json_input'
          }
        ].compact
      end
    },
    custom_action_output: {
      fields: lambda do |_connection, config_fields|
        response_body = { name: 'body' }

        [
          if config_fields['response_type'] == 'raw'
            response_body
          elsif (output = config_fields['output'])
            output_schema = call('format_schema', parse_json(output))
            if output_schema.dig(0, 'type') == 'array' &&
               output_schema.dig(0, 'details', 'fake_array')
              response_body[:type] = 'array'
              response_body[:properties] = output_schema.dig(0, 'properties')
            else
              response_body[:type] = 'object'
              response_body[:properties] = output_schema
            end

            response_body
          end,
          if (headers = config_fields['response_headers'])
            header_props = parse_json(headers)&.map do |field|
              if field[:name].present?
                field[:name] = field[:name].gsub(/\W/, '_').downcase
              elsif field['name'].present?
                field['name'] = field['name'].gsub(/\W/, '_').downcase
              end
              field
            end

            { name: 'headers', type: 'object', properties: header_props }
          end
        ].compact
      end
    },

    company_vendor_insurance_output: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'id', type: 'integer' },
          { name: 'effective_date', type: 'date' },
          { name: 'enable_expired_insurance_notifications', type: 'boolean' },
          { name: 'exempt', type: 'boolean' },
          { name: 'expiration_date', type: 'date' },
          { name: 'info_received', type: 'boolean' },
          { name: 'insurance_provider' },
          { name: 'insurance_type' },
          { name: 'limit' },
          { name: 'notes' },
          { name: 'policy_number' },
          { name: 'status' },
          { name: 'vendor_id', type: 'integer' },
          { name: 'additional_insured' },
          { name: 'division_template' },
          { name: 'insurance_sets' },
          { name: 'origin_data' },
          { name: 'origin_id' }
        ]
      end
    },

    company_vendor_insurance_properties: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'effective_date', type: 'date' },
          { name: 'enable_expired_insurance_notifications',
            type: 'boolean', control_type: 'checkbox',
            render_input: 'boolean_conversion',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'enable_expired_insurance_notifications',
              label: 'Enable expired insurance notifications',
              type: 'string', control_type: 'text',
              render_input: 'boolean_conversion',
              optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are true, false'
            } },
          { name: 'exempt',
            type: 'boolean', control_type: 'checkbox',
            render_input: 'boolean_conversion',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'exempt', label: 'Exempt',
              type: 'string', control_type: 'text',
              render_input: 'boolean_conversion',
              optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are true, false'
            } },
          { name: 'expiration_date', type: 'date' },
          { name: 'info_received',
            type: 'boolean', control_type: 'checkbox',
            render_input: 'boolean_conversion',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'info_received', label: 'Information received',
              type: 'string', control_type: 'text',
              render_input: 'boolean_conversion',
              optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are true, false'
            } },
          { name: 'insurance_type',
            hint: 'Enter the type of insurance, e.g. General Liability' },
          { name: 'limit',
            hint: 'Enter the coverage limit amount, e.g. 1000000.00' },
          { name: 'name', label: 'Provider name',
            hint: 'Enter the insurance provider name, e.g. GL Insurance Inc.' },
          { name: 'notes',
            hint: 'Enter any additional notes, e.g. Meets minimum requirements' },
          { name: 'policy_number',
            hint: 'Enter the policy number, e.g. 12345GL' },
          { name: 'status',
            type: 'string', control_type: 'select',
            pick_list: 'insurance_status_list',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'status', label: 'Status',
              type: :string,
              control_type: 'text',
              optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are compliant, compliant_in_progress, expired, non_compliant, non_compliant_in_progress, undecided, unregistered.'
            } },
          { name: 'additional_insured',
            hint: 'Enter additional insured individuals/companies, e.g. John Doe' },
          { name: 'division_template',
            hint: 'Enter the division template, e.g. Template 1' },
          { name: 'insurance_sets',
            hint: 'Enter the insurance sets, e.g. Set 1' },
          { name: 'origin_data',
            hint: 'Enter the origin data, e.g. OD-2398273424' },
          { name: 'origin_id',
            hint: 'Enter the origin ID, e.g. ABC123' }
        ]
      end
    },

    company_vendor_insurance_input_fields: {
      fields: lambda do |connection, _config_fields|
        [
          { name: 'company_id', label: 'Company',
            type: 'string', optional: false,
            default: connection['company_id'],
            control_type: 'select',
            extends_schema: true,
            pick_list: 'company_list',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'company_id', label: 'Company ID',
              type: :string,
              control_type: 'text',
              extends_schema: true, change_on_blur: true,
              optional: false,
              toggle_hint: 'Use custom value',
              hint: 'Provide ID of the company.'
            } },
          { name: 'vendor_id', label: 'Vendor',
            type: 'string', optional: false,
            control_type: 'select',
            pick_list: 'company_vendor_list',
            pick_list_params: { company_id: 'company_id' },
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'vendor_id', label: 'Vendor ID',
              type: :string,
              control_type: 'text',
              optional: false,
              toggle_hint: 'Use custom value',
              hint: 'Provide ID of the vendor.'
            } }
        ]
      end
    },

    search_object_input: {
      fields: lambda do |connection, config_fields, object_definitions|
        next [] if config_fields.blank? ||
          %w[company company_role].include?(config_fields['object'])

        schema = call('check_default_company', connection)

        if config_fields['object'] == 'project_role'
          schema.concat(call('project_role_search_query_schema'))
        elsif config_fields['object'] == 'company_vendor_insurance'
          object_definitions['company_vendor_insurance_input_fields'].
            concat(
              [
                { name: 'page', type: 'integer', hint: 'Enter the page number to be returned.'},
                { name: 'per_page', type: 'integer',
                  hint: 'Enter the number of records to be returned.' },
              ]
            )
        else
          schema.concat(call("#{config_fields['object']}_search_query_schema")).
            concat(
              [
                { name: 'page', type: 'integer' },
                { name: 'per_page', type: 'integer',
                  hint: 'default: 20, max: 100' },
                { name: 'custom_fields', sticky: true,
                  type: 'string', control_type: 'multiselect',
                  hint: 'Select custom fields of the object.',
                  pick_list: 'custom_field_list',
                  pick_list_params: { company_id: 'company_id' },
                  extends_schema: true,
                  delimiter: ',',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'custom_fields',
                    label: 'Custom fields',
                    extends_schema: true, change_on_blur: true,
                    support_pills: false,
                    optional: true,
                    type: 'string',
                    control_type: 'text',
                    toggle_hint: 'Use custom value',
                    hint: 'Multiple values separated by comma e.g. key1,key2'
                  } }
              ]
            )
        end
      end
    },

    search_object_output: {
      fields: lambda do |_connection, config_fields, object_definitions|
        next [] if config_fields.blank?

        if config_fields['object'] == 'company_vendor_insurance'
          [
            { name: 'records', label: config_fields['object'].pluralize.labelize,
              type: 'array', of: 'object',
              properties: object_definitions['company_vendor_insurance_output'] }
          ]
        else
          [
            { name: 'records', label: config_fields['object'].pluralize.labelize,
              type: 'array', of: 'object',
              properties: call("#{config_fields['object']}_search_schema").
                concat(call('generate_custom_field_output', config_fields)) }
          ]
        end
      end
    },

    get_object_input: {
      fields: lambda do |connection, config_fields, object_definitions|
        next [] if config_fields.blank?

        schema = if %w[project].include?(config_fields['object']) ||
                   config_fields['object'].include?('company_') ||
                   config_fields['object'].include?('project_')
                   optional = connection['company_id'].present?
                   [
                     { name: 'company_id', label: 'Company',
                       type: 'string', optional: optional,
                       default: connection['company_id'],
                       control_type: 'select',
                       extends_schema: true,
                       pick_list: 'company_list',
                       toggle_hint: 'Select from list',
                       toggle_field: {
                         name: 'company_id', label: 'Company ID',
                         type: :string,
                         control_type: 'text',
                         extends_schema: true, change_on_blur: true,
                         optional: optional,
                         toggle_hint: 'Use custom value',
                         hint: 'Provide ID of the company.'
                       } }
                   ]
                 else
                   []
                 end

        unless config_fields['object'] == 'company_vendor_insurance'
          schema = schema.concat([
            { name: 'id', type: 'integer', optional: false,
              label: "#{config_fields['object']&.labelize} ID" },
            { name: 'custom_fields', sticky: true,
              type: 'string', control_type: 'multiselect',
              hint: 'Select custom fields of the object.',
              pick_list: 'custom_field_list',
              pick_list_params: { company_id: 'company_id' },
              extends_schema: true,
              delimiter: ',',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'custom_fields',
                label: 'Custom fields',
                extends_schema: true, change_on_blur: true,
                support_pills: false,
                optional: true,
                type: 'string',
                control_type: 'text',
                toggle_hint: 'Use custom value',
                hint: 'Multiple values separated by comma e.g. key1,key2'
              } }
          ])
        end

        if config_fields['object'].include?('project_')
          schema = schema.concat([
            { name: 'project_id', label: 'Project',
              type: 'string', optional: false,
              control_type: 'select',
              pick_list: 'project_list',
              pick_list_params: { company_id: 'company_id' },
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'project_id', label: 'Project ID',
                type: :string,
                control_type: 'text',
                optional: false,
                toggle_hint: 'Use custom value',
                hint: 'Provide ID of the project.'
              } }
          ])
        elsif config_fields['object'] == 'company_vendor_insurance'
          schema = object_definitions['company_vendor_insurance_input_fields'].concat([
            { name: 'id', type: 'integer', optional: false,
              label: "#{config_fields['object']&.labelize} ID" }
          ])
        elsif config_fields['object'] == 'folder'
          schema = schema.ignored('custom_fields').concat([
            { name: 'project_id', label: 'Project',
              type: 'string', optional: false,
              control_type: 'select',
              pick_list: 'project_list',
              pick_list_params: { company_id: 'company_id' },
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'project_id', label: 'Project ID',
                type: :string,
                control_type: 'text',
                optional: false,
                toggle_hint: 'Use custom value',
                hint: 'Provide ID of the project.'
              } },
            { name: 'exclude_folders', sticky: true,
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              hint: 'If true, exclude child folders from results.',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'exclude_folders',
                label: 'Exclude folders',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'exclude_files', sticky: true,
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              hint: 'If true, exclude child files from results.',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'exclude_files',
                label: 'Exclude files',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } },
            { name: 'show_latest_file_version_only', sticky: true,
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              hint: 'If true, show only the latest file version.',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'show_latest_file_version_only',
                label: 'Show latest file version only',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } }
          ])
        elsif config_fields['object'] == 'file'
          schema = schema.ignored('custom_fields').concat([
            { name: 'project_id', label: 'Project',
              type: 'string', optional: false,
              control_type: 'select',
              pick_list: 'project_list',
              pick_list_params: { company_id: 'company_id' },
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'project_id', label: 'Project ID',
                type: :string,
                control_type: 'text',
                optional: false,
                toggle_hint: 'Use custom value',
                hint: 'Provide ID of the project.'
              } },
            { name: 'show_latest_version_only', sticky: true,
              type: 'boolean', control_type: 'checkbox',
              render_input: 'boolean_conversion',
              hint: 'If true, show only the latest file version.',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'show_latest_file_version_only',
                label: 'Show latest file version only',
                type: 'string', control_type: 'text',
                render_input: 'boolean_conversion',
                optional: true,
                toggle_hint: 'Use custom value',
                hint: 'Allowed values are true, false'
              } }
          ])
        end
        schema
      end
    },

    get_object_output: {
      fields: lambda do |_connection, config_fields, object_definitions|
        next [] if config_fields.blank?

        if config_fields['object'] == 'company_vendor_insurance'
          object_definitions['company_vendor_insurance_output']
        else
          call("#{config_fields['object']}_schema").
            concat(call('generate_custom_field_output', config_fields))
        end
      end
    },

    create_object_input: {
      fields: lambda do |connection, config_fields, object_definitions|
        next [] if config_fields.blank?

        if config_fields['object'] == 'company_vendor_insurance'
          return object_definitions['company_vendor_insurance_input_fields'].concat([
            { name: 'insurance', optional: false, type: 'object',
              properties: object_definitions['company_vendor_insurance_properties'] }
          ])
        end

        schema = call('check_default_company', connection)

        schema.concat(call("#{config_fields['object']}_create_schema")).concat(
          [
            { name: 'custom_fields', sticky: true,
              type: 'string', control_type: 'multiselect',
              hint: 'Select custom fields of the object.',
              pick_list: 'custom_field_list',
              pick_list_params: { company_id: 'company_id' },
              extends_schema: true,
              delimiter: ',',
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'custom_fields',
                label: 'Custom fields',
                extends_schema: true, change_on_blur: true,
                support_pills: false,
                optional: true,
                type: 'string',
                control_type: 'text',
                toggle_hint: 'Use custom value',
                hint: 'Multiple values separated by comma e.g. key1,key2'
              } }
          ]
        ).concat(call('generate_custom_field_input', config_fields))
      end
    },

    create_object_output: {
      fields: lambda do |_connection, config_fields, object_definitions|
        next [] if config_fields.blank? || config_fields['object'] == 'employee_note'

        if config_fields['object'] == 'company_vendor_insurance'
          object_definitions['company_vendor_insurance_output']
        else
          call("#{config_fields['object']}_schema").
            concat(call('generate_custom_field_output', config_fields))
        end
      end
    },

    update_object_input: {
      fields: lambda do |connection, config_fields, object_definitions|
        next [] if config_fields.blank?

        if config_fields['object'] == 'company_vendor_insurance'
          return object_definitions['company_vendor_insurance_input_fields'].concat([
            { name: 'id', type: 'integer', optional: false,
              label: 'Company vendor insurance ID' },
            { name: 'insurance', type: 'object',
              properties: object_definitions['company_vendor_insurance_properties'] }
          ])
        end

        schema = call('check_default_company', connection)

        if config_fields['object'] == 'user_project_role'
          schema.concat(call('user_project_role_schema'))
        else
          schema.concat([
            { name: 'id', type: 'integer', optional: false,
              label: "#{config_fields['object']&.labelize} ID" }
          ]).concat(call("#{config_fields['object']}_update_schema").
          concat(
            [
              { name: 'custom_fields', sticky: true,
                type: 'string', control_type: 'multiselect',
                hint: 'Select custom fields of the object.',
                pick_list: 'custom_field_list',
                pick_list_params: { company_id: 'company_id' },
                extends_schema: true,
                delimiter: ',',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'custom_fields',
                  label: 'Custom fields',
                  extends_schema: true, change_on_blur: true,
                  support_pills: false,
                  optional: true,
                  type: 'string',
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Multiple values separated by comma e.g. key1,key2'
                } }
            ]
          )).concat(call('generate_custom_field_input', config_fields))
        end
      end
    },

    update_object_output: {
      fields: lambda do |_connection, config_fields, object_definitions|
        next [] if config_fields.blank?

        if config_fields['object'] == 'user_project_role'
          call('user_project_role_schema').ignored('project_id')
        elsif config_fields['object'] == 'company_vendor_insurance'
          object_definitions['company_vendor_insurance_output']
        else
          call("#{config_fields['object']}_schema").
            concat(call('generate_custom_field_output', config_fields))
        end
      end
    },

    delete_object_input: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        call('check_default_company', connection).concat(
          [
            { name: 'project_id', label: 'Project',
              type: 'string', optional: false,
              control_type: 'select',
              pick_list: 'project_list',
              pick_list_params: { company_id: 'company_id' },
              toggle_hint: 'Select from list',
              toggle_field: {
                name: 'project_id', label: 'Project ID',
                type: :string,
                control_type: 'text',
                optional: false,
                toggle_hint: 'Use custom value',
                hint: 'Provide ID of the project.'
              } },
            { name: 'id', type: 'integer', optional: false,
              label: "#{config_fields['object']&.labelize} ID" }
          ]
        )
      end
    },

    delete_object_output: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        []
      end
    },

    sync_object_input: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        call('check_default_company', connection).concat([
          { name: 'updates', optional: false,
            label: config_fields['object']&.pluralize&.labelize,
            type: 'array', of: 'object',
            properties: [
              { name: 'id', type: 'integer', sticky: true,
                label: "#{config_fields['object']&.labelize} ID" }
            ].concat(call("#{config_fields['object']}_create_schema").
              ignored('company_id')).concat(
                call('generate_custom_field_input', config_fields)
              ) },
          { name: 'custom_fields', sticky: true,
            type: 'string', control_type: 'multiselect',
            hint: 'Select custom fields of the object.',
            pick_list: 'custom_field_list',
            pick_list_params: { company_id: 'company_id' },
            extends_schema: true,
            delimiter: ',',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'custom_fields',
              label: 'Custom fields',
              extends_schema: true, change_on_blur: true,
              support_pills: false,
              optional: true,
              type: 'string',
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'Multiple values separated by comma e.g. key1,key2'
            } }
        ])
      end
    },

    sync_object_output: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        [
          { name: 'entities',
            type: 'array', of: 'object',
            properties: call("#{config_fields['object']}_schema").
              concat(call('generate_custom_field_output', config_fields)) },
          { name: 'errors',
            type: 'array', of: 'object',
            properties: call("#{config_fields['object']}_schema").
              concat(call('generate_custom_field_output', config_fields)) }
        ]
      end
    },

    trigger_object_input: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        call('check_default_company', connection).concat(
          call("#{config_fields['object']}_trigger_input_schema"))
      end
    },

    trigger_object_output: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        company_id = config_fields['company_id'] || connection['company_id']

        if company_id.present?
          config_fields['custom_fields'] =
            get("custom_field_definitions?company_id=#{company_id}&view=extended").
              map do |custom_field|
                "#{custom_field['data_type']}##{custom_field['id']}##{custom_field['label']}"
              end&.join(',')
        end

        call("#{config_fields['object']}_search_schema").
          concat(call('generate_custom_field_output', config_fields))
      end
    },

    trigger_event_input: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        schema = [
          { name: 'resource_name', label: 'Resource name',
            type: 'string', optional: false,
            control_type: 'select',
            pick_list_params: { object: 'object' },
            pick_list: 'resource_list',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'resource_name',
              label: 'Resource name',
              type: :string,
              control_type: 'text',
              optional: false,
              toggle_hint: 'Use custom value',
              hint: 'E.g. Projects'
            } },
          { name: 'event_type', label: 'Event type',
            type: 'string', optional: false,
            control_type: 'select',
            pick_list: 'event_type_list',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'event_type',
              label: 'Event type',
              type: :string,
              control_type: 'text',
              optional: false,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are create, update, delete.'
            } }
        ]

        if config_fields['object'] == 'company'
          schema = schema.concat(
            [
              { name: 'id', label: 'Company',
                type: 'string', optional: false,
                default: connection['company_id'],
                control_type: 'select',
                pick_list: 'company_list',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'id', label: 'Company ID',
                  type: :string,
                  control_type: 'text',
                  optional: false,
                  toggle_hint: 'Use custom value',
                  hint: 'Provide ID of the company.'
                } }
            ]
          )
        elsif config_fields['object'] == 'project'
          schema = schema.concat(
            [
              { name: 'company_id', label: 'Company',
                type: 'string', optional: connection['company_id'].present?,
                default: connection['company_id'],
                control_type: 'select',
                extends_schema: true,
                pick_list: 'company_list',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'company_id', label: 'Company ID',
                  type: :string,
                  control_type: 'text',
                  extends_schema: true, change_on_blur: true,
                  optional: connection['company_id'].present?,
                  toggle_hint: 'Use custom value',
                  hint: 'Provide ID of the company.'
                } },
              { name: 'id', label: 'Project',
                type: 'string', optional: false,
                control_type: 'select',
                pick_list: 'project_list',
                pick_list_params: { company_id: 'company_id' },
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'id', label: 'Project ID',
                  type: :string,
                  control_type: 'text',
                  optional: false,
                  toggle_hint: 'Use custom value',
                  hint: 'Provide ID of the project.'
                } }
            ]
          )
        end
        schema
      end
    },

    trigger_event_output: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'user_id', type: 'integer' },
          { name: 'ulid' },
          { name: 'timestamp', type: 'date_time' },
          { name: 'resource_name' },
          { name: 'resource_id', type: 'integer' },
          { name: 'project_id', type: 'integer' },
          { name: 'metadata', type: 'object',
            properties: [
              { name: 'source_user_id', type: 'integer' },
              { name: 'source_project_id', type: 'integer' },
              { name: 'source_operation_id', type: 'integer' },
              { name: 'source_company_id', type: 'integer' },
              { name: 'source_application_id', type: 'integer' }
            ] },
          { name: 'id', type: 'integer' },
          { name: 'event_type' },
          { name: 'company_id', type: 'integer' },
          { name: 'api_version' }
        ]
      end
    },

    add_record_object_input: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        schema = call('check_default_company', connection).concat([
          { name: 'project_id', label: 'Project',
            type: 'string', optional: false,
            control_type: 'select',
            pick_list: 'project_list',
            pick_list_params: { company_id: 'company_id' },
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'project_id', label: 'Project ID',
              type: :string,
              control_type: 'text',
              optional: false,
              toggle_hint: 'Use custom value',
              hint: 'Provide ID of the project.'
            } },
          { name: 'id', type: 'integer', optional: false,
            label: "#{config_fields['object']&.labelize} ID" },
          { name: 'custom_fields', sticky: true,
            type: 'string', control_type: 'multiselect',
            hint: 'Select custom fields of the object.',
            pick_list: 'custom_field_list',
            pick_list_params: { company_id: 'company_id' },
            extends_schema: true,
            delimiter: ',',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'custom_fields',
              label: 'Custom fields',
              extends_schema: true, change_on_blur: true,
              support_pills: false,
              optional: true,
              type: 'string',
              control_type: 'text',
              toggle_hint: 'Use custom value',
              hint: 'Multiple values separated by comma e.g. key1,key2'
            } }
        ])

        if config_fields['object'] == 'project_user'
          schema = schema.concat(
            [{ name: 'permission_template_id', type: 'integer',
               render_input: 'integer_conversion' }]
          )
        end
        schema
      end
    },

    add_record_object_output: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        call("#{config_fields['object']}_schema").
          concat(call('generate_custom_field_output', config_fields))
      end
    },

    list_folders_files_input: {
      fields: lambda do |connection, _config_fields|
        call('check_default_company', connection).concat([
          { name: 'project_id', label: 'Project',
            type: 'string', optional: false,
            control_type: 'select',
            pick_list: 'project_list',
            pick_list_params: { company_id: 'company_id' },
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'project_id', label: 'Project ID',
              type: :string,
              control_type: 'text',
              optional: false,
              toggle_hint: 'Use custom value',
              hint: 'Provide ID of the project.'
            } },
          { name: 'exclude_folders', sticky: true,
            type: 'boolean', control_type: 'checkbox',
            render_input: 'boolean_conversion',
            hint: 'If true, exclude child folders from results.',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'exclude_folders',
              label: 'Exclude folders',
              type: 'string', control_type: 'text',
              render_input: 'boolean_conversion',
              optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are true, false'
            } },
          { name: 'exclude_files', sticky: true,
            type: 'boolean', control_type: 'checkbox',
            render_input: 'boolean_conversion',
            hint: 'If true, exclude child files from results.',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'exclude_files',
              label: 'Exclude files',
              type: 'string', control_type: 'text',
              render_input: 'boolean_conversion',
              optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are true, false'
            } },
          { name: 'show_latest_file_version_only', sticky: true,
            type: 'boolean', control_type: 'checkbox',
            render_input: 'boolean_conversion',
            hint: 'If true, show only the latest file version.',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'show_latest_file_version_only',
              label: 'Show latest file version only',
              type: 'string', control_type: 'text',
              render_input: 'boolean_conversion',
              optional: true,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are true, false'
            } }
        ])
      end
    },

    list_folders_files_output: {
      fields: lambda do |_connection, _config_fields|
        call('folder_schema').ignored('folders').
          concat([{ name: 'folders', type: 'array',
                    properties: call('folder_schema') }])
      end
    },

    send_invite_to_user_input: {
      fields: lambda do |connection, _config_fields|
        call('check_default_company', connection).concat(
          [{ name: 'id', label: 'Company user ID', optional: false }]
        )
      end
    },

    download_input: {
      fields: lambda do |_connection|
        [
          {
            name: 'file_id',
            optional: false,
            hint: 'ID of the file to download.'
          },
          { name: 'project_id', label: 'Project',
            type: 'string', optional: false,
            control_type: 'select',
            pick_list: 'download_project_list',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'project_id', label: 'Project ID',
              type: :string,
              control_type: 'text',
              optional: false,
              toggle_hint: 'Use custom value',
              hint: 'Provide ID of the project.'
            } }
        ]
      end
    }
  },

  actions: {
    custom_action: {
      deprecated: true,
      subtitle: 'Build your own Procore action with a HTTP request',

      description: lambda do |object_value, _object_label|
        "<span class='provider'>" \
        "#{object_value[:action_name] || 'Custom action'}</span> in " \
        "<span class='provider'>Procore</span>"
      end,

      help: {
        body: 'Build your own Procore action with a HTTP request. ' \
        'The request will be authorized with your Procore connection.',
        learn_more_url: 'https://developers.procore.com/reference/rest/v1/authentication',
        learn_more_text: 'Procore API documentation'
      },

      config_fields: [
        {
          name: 'action_name',
          hint: "Give this action you're building a descriptive name, e.g. " \
          'create record, get record',
          default: 'Custom action',
          optional: false,
          schema_neutral: true
        },
        {
          name: 'verb',
          label: 'Method',
          hint: 'Select HTTP method of the request',
          optional: false,
          control_type: 'select',
          pick_list: %w[get post put patch delete].
                       map { |verb| [verb.upcase, verb] }
        }
      ],

      input_fields: lambda do |object_definition|
        object_definition['custom_action_input']
      end,

      execute: lambda do |_connection, input|
        verb = input['verb']
        if %w[get post put patch options delete].exclude?(verb)
          error("#{verb.upcase} not supported")
        end
        path = input['path']
        data = input.dig('input', 'data') || {}
        if input['request_type'] == 'multipart'
          data = data.each_with_object({}) do |(key, val), hash|
            hash[key] = if val.is_a?(Hash)
                          [val[:file_content],
                           val[:content_type],
                           val[:original_filename]]
                        else
                          val
                        end
          end
        end
        request_headers = input['request_headers']
          &.each_with_object({}) do |item, hash|
          hash[item['key']] = item['value']
        end || {}
        request = case verb
                  when 'get'
                    get(path, data)
                  when 'post'
                    if input['request_type'] == 'raw'
                      post(path).request_body(data)
                    else
                      post(path, data)
                    end
                  when 'put'
                    if input['request_type'] == 'raw'
                      put(path).request_body(data)
                    else
                      put(path, data)
                    end
                  when 'patch'
                    if input['request_type'] == 'raw'
                      patch(path).request_body(data)
                    else
                      patch(path, data)
                    end
                  when 'options'
                    options(path, data)
                  when 'delete'
                    delete(path, data)
                  end.case_sensitive_headers(request_headers)
        request = case input['request_type']
                  when 'url_encoded_form'
                    request.request_format_www_form_urlencoded
                  when 'multipart'
                    request.request_format_multipart_form
                  else
                    request
                  end
        response =
          if input['response_type'] == 'raw'
            request.response_format_raw
          else
            request
          end.
            after_error_response(/.*/) do |code, body, headers, message|
            error({ code: code, message: message, body: body, headers: headers }.
              to_json)
          end

        response.after_response do |_code, res_body, res_headers|
          {
            body: res_body ? call('format_response', res_body) : nil,
            headers: res_headers
          }
        end
      end,

      output_fields: lambda do |object_definition|
        object_definition['custom_action_output']
      end
    },

    search_records: {
      title: 'Search records',
      subtitle: 'Search records, e.g. folder, in Procore',
      description: lambda do |_input, search_object_list|
        "Search <span class='provider'>" \
        "#{search_object_list[:object]&.pluralize || 'records'}</span> " \
        'in <span class="provider">Procore</span>'
      end,

      help: 'Returns all records that matches your search criteria.',

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :search_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['search_object_input']
      end,

      execute: lambda do |_connection, input|
        if input.dig('filters', 'created_at')
          input['filters']['created_at'] = call('format_date_time_range',
                                                input['filters']['created_at'])
        end
        if input.dig('filters', 'updated_at')
          input['filters']['updated_at'] = call('format_date_time_range',
                                                input['filters']['updated_at'])
        end

        response = get(call('get_url', input), input.except('object')).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end

        response&.each do |record|
          if record['custom_fields'].present?
            record['custom_fields'] = call('format_custom_field_response',
                                           record['custom_fields'])
          end
        end
        { records: response }
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['search_object_output']
      end,

      sample_output: lambda do |_connection, input|
        input['per_page'] = 1
        { records: get(call('get_url', input), input) }
      end
    },

    get_record: {
      title: 'Get record details by ID',
      subtitle: 'Retrieve the details of record, e.g. project, via its ID in Procore',
      description: lambda do |_input, get_object_list|
        "Get <span class='provider'>" \
        "#{get_object_list[:object] || 'record'}</span> details by ID " \
        'in <span class="provider">Procore</span>'
      end,

      help: 'Retrieve the details of record, e.g. project by project ID.',

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :get_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['get_object_input']
      end,

      execute: lambda do |_connection, input|
        response = get("#{call('get_url', input)}/#{input['id']}",
                       input.except('object', 'id')).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end

        if response['custom_fields'].present?
          response['custom_fields'] = call('format_custom_field_response',
                                           response['custom_fields'])
        end
        response
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['get_object_output']
      end,

      sample_output: lambda do |_connection, input|
        input['per_page'] = 1
        get(call('get_url', input), input)&.first
      end
    },

    create_record: {
      title: 'Create record',
      subtitle: 'Create record, e.g. folder, in Procore',
      description: lambda do |_input, create_object_list|
        "Create <span class='provider'>" \
        "#{create_object_list[:object] || 'record'}</span> " \
        'in <span class="provider">Procore</span>'
      end,

      help: 'Create a record, e.g. project, in Procore.',

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :create_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['create_object_input']
      end,

      execute: lambda do |connection, input|
        input['company_id'] = connection['company_id'] if input['company_id'].blank?
        payload = call('format_request_payload',
                       input.except('id', 'custom_fields'))
        request = post(call('get_url', input), payload)
        if %w[folder file].include? input['object']
          request = request.params(input.slice('project_id', 'company_id'))
        end
        if %w[company_user project_user file].include? input['object']
          request = request.request_format_multipart_form
        end

        response = request.
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end

        if response['custom_fields'].present?
          response['custom_fields'] = call('format_custom_field_response',
                                           response['custom_fields'])
        end
        response
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['create_object_output']
      end,

      sample_output: lambda do |_connection, input|
        input['per_page'] = 1
        get(call('get_url', input), input)&.first
      end
    },

    update_record: {
      title: 'Update record',
      subtitle: 'Update record, e.g. folder, in Procore',
      description: lambda do |_input, update_object_list|
        "Update <span class='provider'>" \
        "#{update_object_list[:object] || 'record'}</span> " \
        'in <span class="provider">Procore</span>'
      end,

      help: 'Update a record, e.g. project, in Procore.',

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :update_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['update_object_input']
      end,

      execute: lambda do |connection, input|
        input['company_id'] = connection['company_id'] if input['company_id'].blank?
        if input['object'] == 'company_vendor_insurance'
          insurance_update = { id: input['id'] }.merge(input['insurance'] || {})
          response = patch("#{call('get_url', input)}/sync",
                           { updates: [insurance_update] }).
                     after_error_response(/.*/) do |_code, body, _header, message|
                       error("#{message}: #{body}")
                     end

          (response['entities']&.first || response['errors']&.first || response)
        else
          payload = call('format_request_payload',
                         input.except('id', 'custom_fields'))
          request = patch("#{call('get_url', input)}/#{input['id']}", payload)
          if %w[folder file].include? input['object']
            request = request.params(input.slice('project_id', 'company_id'))
          end
          if %w[company_user project_user file].include? input['object']
            request = request.request_format_multipart_form
          end

          response = request.
                     after_error_response(/.*/) do |_code, body, _header, message|
                       error("#{message}: #{body}")
                     end

          if response['custom_fields'].present?
            response['custom_fields'] = call('format_custom_field_response',
                                             response['custom_fields'])
          end
          response
        end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['update_object_output']
      end,

      sample_output: lambda do |_connection, input|
        input['per_page'] = 1
        get(call('get_url', input), input)&.first
      end
    },

    delete_record: {
      title: 'Delete record',
      subtitle: 'Detete record, e.g. folder, in Procore',
      description: lambda do |_input, delete_object_list|
        "Delete <span class='provider'>" \
        "#{delete_object_list[:object] || 'record'}</span> " \
        'in <span class="provider">Procore</span>'
      end,

      help: 'Delete a record, e.g. project, in Procore.',

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :delete_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['delete_object_input']
      end,

      execute: lambda do |_connection, input|
        delete("#{input['object'].pluralize}/#{input['id']}").
          params(input.except('object', 'id')).
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['delete_object_output']
      end
    },

    sync_records: {
      title: 'Sync records',
      subtitle: 'Create or update records in batch, e.g. user, in Procore',
      description: lambda do |_input, sync_object_list|
        "Create or update <span class='provider'>" \
        "#{sync_object_list[:object]&.pluralize || 'records'}</span> " \
        'in batch in <span class="provider">Procore</span>'
      end,

      help: 'Create or update records in batch, e.g. projects, in Procore.',

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :sync_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['sync_object_input']
      end,

      execute: lambda do |_connection, input|
        response = patch("#{call('get_url', input)}/sync",
                         input.except('object', 'custom_fields')).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end

        response['entities']&.each do |record|
          if record['custom_fields'].present?
            record['custom_fields'] = call('format_custom_field_response',
                                           record['custom_fields'])
          end
        end
        response['errors']&.each do |record|
          if record['custom_fields'].present?
            record['custom_fields'] = call('format_custom_field_response',
                                           record['custom_fields'])
          end
        end
        response
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['sync_object_output']
      end,

      sample_output: lambda do |_connection, input|
        input['per_page'] = 1
        response = get(call('get_url', input), input)
        { entities: response, errors: response }
      end
    },

    add_record_to_project: {
      title: 'Add record to project',
      subtitle: 'Add record to project, e.g. user, in Procore',
      description: lambda do |_input, sync_object_list|
        "Add <span class='provider'>" \
        "#{sync_object_list[:object] || 'record'}</span> " \
        'to project in <span class="provider">Procore</span>'
      end,

      help: 'Add record to project, e.g. vendor, in Procore.',

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :add_record_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['add_record_object_input']
      end,

      execute: lambda do |_connection, input|
        payload = if input['object'] == 'project_user'
                    { user: {
                      permission_template_id: input['permission_template_id']
                    } }
                  end
        response = post("#{call('get_url', input)}/#{input['id']}/actions/add",
                        payload).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end
        if response['custom_fields'].present?
          response['custom_fields'] = call('format_custom_field_response',
                                           response['custom_fields'])
        end
        response
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['add_record_object_output']
      end,

      sample_output: lambda do |_connection, input|
        input['per_page'] = 1
        get(call('get_url', input), input)&.first
      end
    },

    remove_record_to_project: {
      title: 'Remove/delete record from project',
      subtitle: 'Remove or delete record from project, e.g. user, in Procore',
      description: lambda do |_input, sync_object_list|
        "Remove or delete <span class='provider'>" \
        "#{sync_object_list[:object] || 'record'}</span> " \
        'from project in <span class="provider">Procore</span>'
      end,

      help: 'Remove or delete record to project, e.g. vendor, in Procore.',

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :add_record_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['add_record_object_input'].
          only('company_id', 'project_id', 'id')
      end,

      execute: lambda do |_connection, input|
        delete("#{call('get_url', input)}/#{input['id']}/actions/remove").
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end
      end
    },

    send_invite_to_user: {
      title: 'Send invite to company user',
      subtitle: 'Send invite email to company user in Procore',
      description: 'Send invite to company user in Procore',

      help: 'Send invite email to specified company user in Procore.',

      input_fields: lambda do |object_definitions|
        object_definitions['send_invite_to_user_input']
      end,

      execute: lambda do |_connection, input|
        patch("companies/#{input['company_id']}/users/#{input['id']}/invite").
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end
      end
    },

    list_folders_files: {
      title: 'List folders and files',
      subtitle: 'List folders and files in Procore',
      description: 'List folders and files in Procore',

      help: 'Returns a list of folders and files for a specified project. ' \
      'Note: this operation will return all of the folders and files within ' \
      "the root folder of that project's document structure.",

      input_fields: lambda do |object_definitions|
        object_definitions['list_folders_files_input']
      end,

      execute: lambda do |_connection, input|
        get('folders', input).
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['list_folders_files_output']
      end
    },

    download_file: {
      title: 'Download file',
      description: "Download a specific <span class='provider'>file</span>
      via its ID in<span class='provider'>Procore</span>",
      subtitle: 'Downloads a specific file, in Procore, via its ID',
      help: 'Download any specific file, in Procore, via its ID',

      input_fields: lambda do |object_definitions|
        object_definitions['download_input']
      end,
      execute: lambda do |_connection, input|
        get("files/#{input['file_id']}", input.except('file_id')).
          after_response do |code, body, _header|
          if code == 200 && body['file_versions'].present?
            url = body['file_versions']&.dig(0, 'url')
            get(url).ignore_redirection.after_response do |code, body, header|
              if (300..399).include?(code) && header['location'].present?
                file_content = get(header['location']).response_format_raw.
                  after_error_response(/.*/) do |_code, err, _header, message|
                    error("#{message}: #{err}")
                  end
                { file_content: file_content }
              else
                body
              end
            end
          else
            body
          end
        end
      end,

      output_fields: lambda do |_object_definitions|
        [
          {
            name: 'file_content'
          }
        ]
      end,

      sample_output: lambda do |_connection, _input|
        {
          file_content: 'JVBERi0xLjEKJcKlwrHDqwoKMSAwIG9iagogIDw8IC9UeXBlIC9DYXRhbG9nCiAgICAgL1BhZ2'
        }
      end
    },
 migrate_provider: {
      title: "Migrate Provider in Recipe JSON",
      description: "Replace provider values in recipe JSON",

      input_fields: lambda do |_connection, _config|
        [
          {
            name: "recipe_json",
            label: "Recipe JSON",
            type: :object,
            optional: false
          },
          {
            name: "old_provider",
            label: "Old Provider Name",
            type: :string,
            optional: false
          },
          {
            name: "new_provider",
            label: "New Provider Name",
            type: :string,
            optional: false
          }
        ]
      end,

      execute: lambda do |_connection, input|
        raise "Recipe JSON is required" if input["recipe_json"].blank?
        raise "Old/New provider required" if input["old_provider"].blank? || input["new_provider"].blank?

        old_name = input["old_provider"]
        new_name = input["new_provider"]

        # Convert JSON → string
        json_string = input["recipe_json"].to_json

        # Replace ONLY provider values safely
        # This ensures we only replace `"provider":"old"`
        updated_string = json_string.gsub(
          "\"provider\":\"#{old_name}\"",
          "\"provider\":\"#{new_name}\""
        )

        # Convert back to JSON
        updated_json = JSON.parse(updated_string)

        {
          updated_recipe:{},
          old_provider: old_name,
          new_provider: new_name
        }
      end,

      output_fields: lambda do |_connection, _config|
        [
          { name: "updated_recipe", type: :object },
          { name: "old_provider", type: :string },
          { name: "new_provider", type: :string }
        ]
      end
    },

      update_provider_reference: {
      title: 'Update Provider References (String Input)',
      description: 'Accepts JSON string, replaces provider references, returns updated string',
 
      input_fields: lambda do
        [
          {
            name: 'recipe_json_string',
            label: 'Recipe JSON (String)',
            type: 'string',
            optional: false
          },
          {
            name: 'old_provider',
            label: 'Old Provider',
            type: 'string',
            optional: false
          },
          {
            name: 'new_provider',
            label: 'New Provider',
            type: 'string',
            optional: false
          },
          {
            name:'config_field',
            label:'Config Field',
            type:'string',
            optional:false
          }
        ]
      end,
 
      execute: lambda do |connection, input|
 
        # -----------------------------
        # Step 1: String → JSON
        # -----------------------------
        parsed_json = parse_json(input['recipe_json_string'])
 
        # -----------------------------
        # Step 2: Deep Replace
        # -----------------------------
        updated_json = call(
          :deep_replace,
          parsed_json,
          input['old_provider'],
          input['new_provider']
        )
        if(!updated_json['config'].blank?)
            updated_json['config'].append(parse_json(input['config_field']))
        end
        # -----------------------------
        # Step 3: JSON → String
        # -----------------------------
        updated_string = updated_json.to_json
        puts(updated_string)
 
        {
          updated_recipe_string: updated_string
        }
      end,
 
      output_fields: lambda do
        [
          {
            name: 'updated_recipe_string',
            type: 'string'
          }
        ]
      end
    }
  },

  triggers: {
    new_record: {
      title: 'New record',
      subtitle: 'Triggers when a record is created. e.g. project',
      description: lambda do |_connection, trigger_object_list|
        "New <span class='provider'>" \
        "#{trigger_object_list[:object] || 'record'}</span> "\
        ' in <span class="provider">Procore</span>'
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :trigger_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        [
          {
            name: 'since',
            type: 'timestamp',
            label: 'When first started, this recipe should pick up events from',
            hint: 'When you start recipe for the first time, ' \
            'it picks up trigger events from this specified date and time. ' \
            'Leave empty to get records created or updated one hour ago',
            sticky: true
          }
        ].concat(object_definitions['trigger_object_input'])
      end,

      poll: lambda do |_connection, input, closure|
        closure ||= {}
        page = closure['page'] || 1
        limit = 100
        created_from = closure&.[]('created_from') ||
                       (input['since'] || 1.hour.ago).to_time.iso8601
        created_to = closure&.[]('created_to') || Time.now.iso8601

        input['filters'] = { 'created_at' => "#{created_from}...#{created_to}" }.
                           merge(input['filters'] || {})
        input['page'] = page
        input['per_page'] = 100

        response = get(call('get_url', input), input.except('object')).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end || []

        response.each do |record|
          if record['custom_fields'].present?
            record['custom_fields'] = call('format_custom_field_response',
                                           record['custom_fields'])
          end
        end

        closure = if (has_more = (response.size >= limit))
                    { 'created_from': created_from,
                      'created_to': created_to,
                      'page': page + 1 }
                  else
                    { 'created_from': created_to,
                      'created_to': nil,
                      'page': 1 }
                  end

        {
          events: response,
          next_poll: closure,
          can_poll_more: has_more
        }
      end,

      dedup: lambda do |item|
        item['id']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['trigger_object_output']
      end,

      sample_output: lambda do |_connection, input|
        get(call('get_url', input), per_page: 1)&.first
      end
    },

    new_updated_record: {
      title: 'New/updated record',
      subtitle: 'Triggers when a record is created or updated. e.g. person',
      description: lambda do |_connection, trigger_object_list|
        "New or updated <span class='provider'>" \
        "#{trigger_object_list[:object] || 'record'}</span> "\
        ' in <span class="provider">Procore</span>'
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :trigger_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        [
          {
            name: 'since',
            type: 'timestamp',
            label: 'When first started, this recipe should pick up events from',
            hint: 'When you start recipe for the first time, ' \
            'it picks up trigger events from this specified date and time. ' \
            'Leave empty to get records created or updated one hour ago',
            sticky: true
          }
        ].concat(object_definitions['trigger_object_input'])
      end,

      poll: lambda do |_connection, input, closure|
        closure ||= {}
        page = closure['page'] || 1
        limit = 100
        updated_from = closure&.[]('updated_from') ||
                       (input['since'] || 1.hour.ago).to_time.iso8601
        updated_to = closure&.[]('updated_to') || Time.now.iso8601

        input['filters'] = { 'updated_at' => "#{updated_from}...#{updated_to}" }.
                           merge(input['filters'] || {})
        input['page'] = page
        input['per_page'] = 100

        response = get(call('get_url', input), input.except('object')).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end || []

        response.each do |record|
          if record['custom_fields'].present?
            record['custom_fields'] = call('format_custom_field_response',
                                           record['custom_fields'])
          end
        end

        closure = if (has_more = (response.size >= limit))
                    { 'updated_from': updated_from,
                      'updated_to': updated_to,
                      'page': page + 1 }
                  else
                    { 'updated_from': updated_to,
                      'updated_to': nil,
                      'page': 1 }
                  end

        {
          events: response,
          next_poll: closure,
          can_poll_more: has_more
        }
      end,

      dedup: lambda do |item|
        "#{item['id']}@#{item['updated_at']}"
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['trigger_object_output']
      end,

      sample_output: lambda do |_connection, input|
        get(call('get_url', input), per_page: 1)&.first
      end
    },

    new_event: {
      title: 'New event',
      subtitle: 'Triggers immediately when new event occurs in Procore',
      description: lambda do |_input, trigger_event_list|
        "New <span class='provider'>" \
        "#{trigger_event_list[:object]} events</span> "\
        ' in <span class="provider">Procore</span>'
      end,

      help: 'Triggered when an event is occured e.g. a new project is created.',

      config_fields: [
        { name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :trigger_event_list,
          hint: 'Select the object from list.' }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['trigger_event_input']
      end,

      webhook_subscribe: lambda do |webhook_url, _connection, input, recipe_id|
        payload = {
          "#{input['object']}_id" => input['id'],
          'hook': {
            'api_version': 'v2',
            'namespace': "workato-#{recipe_id}",
            'destination_url': webhook_url
          }
        }

        hook = post('webhooks/hooks', payload).
               after_error_response(/.*/) do |_code, body, _header, message|
                 error("#{message}: #{body}")
               end

        payload2 = {
          "#{input['object']}_id" => input['id'],
          'api_version': 'v2',
          'trigger': {
            'resource_name': input['resource_name'],
            'event_type': input['event_type']
          }
        }

        post("webhooks/hooks/#{hook['id']}/triggers", payload2).
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end
      end,

      webhook_notification: lambda do |input, payload|
        payload if payload['resource_name'] == input['resource_name']
      end,

      webhook_unsubscribe: lambda do |webhook|
        params = {
          company_id: webhook['company_id'],
          project_id: webhook['project_id']
        }
        delete("webhooks/hooks/#{webhook['webhook_hook_id']}/triggers/" \
          "#{webhook['id']}", params)
        delete("webhooks/hooks/#{webhook['webhook_hook_id']}", params)
      end,

      dedup: lambda do |item|
        "#{item['ulid']}@#{item['timestamp']}"
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['trigger_event_output']
      end,

      sample_output: lambda do |_connection, _input|
        {
          user_id: 46_725,
          ulid: '01F5J8BTQ75E6WB9QW3BVM8C94',
          timestamp: '2021-05-13T06:59:27.713236Z',
          resource_name: 'Notes Logs',
          resource_id: 6606,
          project_id: 39_577,
          metadata: {
            source_user_id: 46_725,
            source_project_id: 39_577,
            source_operation_id: '0181c891',
            source_company_id: 30_769,
            source_application_id: '124324'
          },
          id: 266_471_964,
          event_type: 'update',
          company_id: 30_769,
          api_version: 'v2'
        }
      end
    }
  },

  pick_lists: {
    search_object_list: lambda do |_connection|
      [
        %w[Project project],
        %w[Company company],
        %w[Company\ user company_user],
        %w[Inactive\ company\ user company_user_inactive],
        %w[Project\ user project_user],
        %w[Inactive\ project\ user project_user_inactive],
        %w[Company\ vendor company_vendor],
        %w[Company\ vendor\ insurance company_vendor_insurance],
        %w[Inactive\ company\ vendor company_vendor_inactive],
        %w[Project\ vendor project_vendor],
        %w[Inactive\ project\ vendor project_vendor_inactive],
        %w[Company\ person company_person],
        %w[Inactive\ company\ person company_person_inactive],
        %w[Project\ person project_person],
        %w[Inactive\ project\ person project_person_inactive],
        %w[Company\ roles company_role],
        %w[Project\ roles project_role]
      ]
    end,

    get_object_list: lambda do |_connection|
      [
        %w[Project project],
        %w[Company\ user company_user],
        %w[Project\ user project_user],
        %w[Company\ vendor company_vendor],
        %w[Company\ vendor\ insurance company_vendor_insurance],
        %w[Project\ vendor project_vendor],
        %w[Folder folder],
        %w[File file]
      ]
    end,

    create_object_list: lambda do |_connection|
      [
        %w[Project project],
        %w[Company\ user company_user],
        %w[Project\ user project_user],
        %w[Company\ vendor company_vendor],
        %w[Company\ vendor\ insurance company_vendor_insurance],
        %w[Project\ vendor project_vendor],
        %w[Project\ person project_person],
        %w[Folder folder],
        %w[File file]
      ]
    end,

    update_object_list: lambda do |_connection|
      [
        %w[Project project],
        %w[Company\ user company_user],
        %w[Project\ user project_user],
        %w[Company\ vendor company_vendor],
        %w[Company\ vendor\ insurance company_vendor_insurance],
        %w[Project\ vendor project_vendor],
        %w[Company\ person company_person],
        %w[Project\ person project_person],
        %w[Folder folder],
        %w[File file],
        %w[User\ project\ role user_project_role]
      ]
    end,

    delete_object_list: lambda do |_connection|
      [
        # %w[Project project],
        %w[Folder folder],
        %w[File file]
      ]
    end,

    sync_object_list: lambda do |_connection|
      [
        %w[Project project],
        %w[Company\ user company_user],
        %w[Company\ vendor company_vendor]
      ]
    end,

    trigger_object_list: lambda do |_connection|
      [
        %w[Project project],
        %w[Company\ user company_user]
      ]
    end,

    add_record_object_list: lambda do |_connection|
      [
        %w[Vendor project_vendor],
        %w[Company\ user project_user]
      ]
    end,

    project_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("projects?company_id=#{company_id}").map do |project|
        [
          project['name'],
          project['id']
        ]
      end || []
    end,

    company_list: lambda do |_connection|
      get('companies').map do |company|
        [
          company['name'],
          company['id']
        ]
      end || []
    end,

    download_project_list: lambda do |connection|
      company_id = connection['company_id']
      get("projects?company_id=#{company_id}")&.map do |project|
        [
          project['name'],
          project['id']
        ]
      end || []
    end,

    company_vendor_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("/rest/v1.0/vendors?company_id=#{company_id}view=compact").
        map do |vendor|
          [
            vendor['name'],
            vendor['id']
          ]
        end || []
    end,

    company_role_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("/rest/v1.0/companies/#{company_id}/roles").
        map do |role|
          [
            role['name'],
            role['id']
          ]
        end || []
    end,

    project_vendor_list: lambda do |_connection, project_id:|
      next [] if project_id.blank? || project_id.include?("{_('data.") ||
                 project_id.include?('pill_type')

      get("/rest/v1.0/projects/#{project_id}/vendors?view=compact").
        map do |vendor|
          [
            vendor['name'],
            vendor['id']
          ]
        end || []
    end,

    project_stage_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("companies/#{company_id}/project_stages").map do |project_stage|
        [
          project_stage['name'],
          project_stage['id']
        ]
      end || []
    end,

    office_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("offices?company_id=#{company_id}").map do |office|
        [
          office['name'],
          office['id']
        ]
      end || []
    end,

    program_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("companies/#{company_id}/programs").map do |program|
        [
          program['name'],
          program['id']
        ]
      end || []
    end,

    project_bid_type_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("companies/#{company_id}/project_bid_types").map do |project_bid_type|
        [
          project_bid_type['name'],
          project_bid_type['id']
        ]
      end || []
    end,

    project_owner_type_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("companies/#{company_id}/project_owner_types").map do |project_owner_type|
        [
          project_owner_type['name'],
          project_owner_type['id']
        ]
      end || []
    end,

    project_region_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("companies/#{company_id}/project_regions").map do |project_region|
        [
          project_region['name'],
          project_region['id']
        ]
      end || []
    end,

    project_type_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("companies/#{company_id}/project_types").map do |project_type|
        [
          project_type['name'],
          project_type['id']
        ]
      end || []
    end,

    project_template_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("project_templates?company_id=#{company_id}").map do |project_template|
        [
          project_template['name'],
          project_template['id']
        ]
      end || []
    end,

    custom_field_list: lambda do |connection, company_id:|
      company_id = call('get_company_id', connection, company_id)
      next [] if company_id.blank?

      get("custom_field_definitions?company_id=#{company_id}&view=extended").
        map do |custom_field|
        [
          custom_field['label'],
          "#{custom_field['data_type']}##{custom_field['id']}##{custom_field['label']}"
        ]
      end || []
    end,

    resource_list: lambda do |_connection, object:|
      {
        'project' => [
          %w[Images Images],
          ['Image Categories', 'Image Categories'],
          ['Markup Layers', 'Markup Layers'],
          ['Pdf Download Pages', 'Pdf Download Pages'],
          ['Drawing Areas', 'Drawing Areas'],
          %w[Drawings Drawings],
          ['Drawing Uploads', 'Drawing Uploads'],
          ['Drawing Sets', 'Drawing Sets'],
          ['Coordination Issues', 'Coordination Issues'],
          ['Prime Contract Line Items', 'Prime Contract Line Items'],
          ['Prime Contracts', 'Prime Contracts'],
          ['Direct Cost Line Items', 'Direct Cost Line Items'],
          ['Direct Costs', 'Direct Costs'],
          ['Work Order Contracts', 'Work Order Contracts'],
          ['Work Order Contract Line Items', 'Work Order Contract Line Items'],
          %w[RFQs RFQs],
          ['RFQ Responses', 'RFQ Responses'],
          ['Purchase Order Contract Line Items', 'Purchase Order Contract Line Items'],
          ['Purchase Order Contracts', 'Purchase Order Contracts'],
          ['Contract Payments', 'Contract Payments'],
          ['RFQ Quotes', 'RFQ Quotes'],
          ['Potential Change Orders', 'Potential Change Orders'],
          ['Change Order Requests', 'Change Order Requests'],
          ['Potential Change Order Line Items', 'Potential Change Order Line Items'],
          ['Change Order Packages', 'Change Order Packages'],
          ['Change Events', 'Change Events'],
          ['Site Instructions', 'Site Instructions'],
          ['File Versions', 'File Versions'],
          ['Inspection Checklists', 'Inspection Checklists'],
          ['Payment Applications', 'Payment Applications'],
          ['Draw Requests', 'Draw Requests'],
          ['Equipment Logs', 'Equipment Logs'],
          ['Bim Model Revisions', 'Bim Model Revisions'],
          ['Daily Logs', 'Daily Logs'],
          ['Coordination Issue Activities', 'Coordination Issue Activities'],
          ['Bim Models', 'Bim Models'],
          ['Daily Log/Entries', 'Daily Log/Entries'],
          ['Bim File Extractions', 'Bim File Extractions'],
          ['Punch Items', 'Punch Items'],
          ['Observation Item Response Logs', 'Observation Item Response Logs'],
          ['Observation Items', 'Observation Items'],
          %w[Incidents Incidents],
          ['Work Logs', 'Work Logs'],
          ['Weather Logs', 'Weather Logs'],
          ['Waste Logs', 'Waste Logs'],
          ['Visitor Logs', 'Visitor Logs'],
          ['Safety Violation Logs', 'Safety Violation Logs'],
          ['Quantity Logs', 'Quantity Logs'],
          ['Productivity Logs', 'Productivity Logs'],
          ['Plan Revision Logs', 'Plan Revision Logs'],
          ['Manpower Logs', 'Manpower Logs'],
          ['Daily Construction Report Logs', 'Daily Construction Report Logs'],
          ['Dumpster Logs', 'Dumpster Logs'],
          ['Inspection Logs', 'Inspection Logs'],
          ['Delivery Logs', 'Delivery Logs'],
          ['Accident Logs', 'Accident Logs'],
          ['Notes Logs', 'Notes Logs'],
          ['Budget View Snapshots', 'Budget View Snapshots'],
          ['Budget Modifications', 'Budget Modifications'],
          ['Budget Line Items', 'Budget Line Items'],
          %w[Forms Forms],
          ['Call Logs', 'Call Logs'],
          ['Task Items', 'Task Items'],
          ['Project Insurances', 'Project Insurances'],
          ['Project Users', 'Project Users'],
          ['Project Vendors', 'Project Vendors'],
          ['Project Folders', 'Project Folders'],
          ['Project Files', 'Project Files'],
          ['Project File Versions', 'Project File Versions'],
          ['Project Dates', 'Project Dates'],
          %w[Locations Locations],
          ['Sub Jobs', 'Sub Jobs'],
          ['Cost Codes', 'Cost Codes'],
          ['Timecard Entries', 'Timecard Entries'],
          %w[ToDos ToDos],
          %w[Tasks Tasks],
          ['Submittal Packages', 'Submittal Packages'],
          %w[Submittals Submittals],
          ['Specification Section Divisions', 'Specification Section Divisions'],
          ['Specification Sets', 'Specification Sets'],
          ['Specification Section Revisions', 'Specification Section Revisions'],
          ['Specification Sections', 'Specification Sections'],
          %w[RFIs RFIs],
          ['RFI Replies', 'RFI Replies'],
          ['Meeting Topics', 'Meeting Topics'],
          ['Meeting Categories', 'Meeting Categories'],
          %w[Meetings Meetings],
          ['Meeting Attendees', 'Meeting Attendees']
        ],
        'company' => [
          ['Line Item Types', 'Line Item Types'],
          ['Form Templates', 'Form Templates'],
          ['Standard Cost Codes', 'Standard Cost Codes'],
          ['Standard Cost Code Lists', 'Standard Cost Code Lists'],
          %w[Projects Projects],
          %w[Trades Trades],
          ['Project Types', 'Project Types'],
          ['Project Owner Types', 'Project Owner Types'],
          ['Project Stages', 'Project Stages'],
          ['Project Regions', 'Project Regions'],
          ['Project Bid Types', 'Project Bid Types'],
          %w[Programs Programs],
          %w[Offices Offices],
          %w[Departments Departments],
          ['Company Vendors', 'Company Vendors'],
          ['Company Users', 'Company Users'],
          ['Company Insurances', 'Company Insurances'],
          ['Company Folders', 'Company Folders'],
          ['Company Files', 'Company Files'],
          ['Company File Versions', 'Company File Versions'],
          ['ERP Requests', 'ERP Requests'],
          ['Change Types', 'Change Types'],
          ['Change Order Change Reasons', 'Change Order Change Reasons'],
          ['Timecard Time Types', 'Timecard Time Types'],
          %w[Bids Bids]
        ]
      }[object]
    end,

    trigger_event_list: lambda do |_connection|
      [
        %w[Company company],
        %w[Project project]
      ]
    end,

    event_type_list: lambda do |_connection|
      [
        %w[Create create],
        %w[Update update],
        %w[Delete delete]
      ]
    end,

    insurance_status_list: lambda do |_connection|
      [
        %w[Compliant compliant],
        %w[Compliant\ in\ progress compliant_in_progress],
        %w[Expired expired],
        %w[Non\ compliant non_compliant],
        %w[Non\ compliant\ in\ progress non_compliant_in_progress],
        %w[Undecided undecided],
        %w[Unregistered unregistered]
      ]
    end
  }


}