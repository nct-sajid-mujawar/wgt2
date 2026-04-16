# THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
# ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
{
  title: 'Autodesk Construction Cloud',
  connection: {
    fields: [
      {
        name: 'client_id',
        optional: false,
        hint: 'Enter the Client ID from your APS application. ' \
        'Click <a href="https://tutorials.autodesk.io/#create-app-credentials">here</a> ' \
        'to learn how to generate Client ID. When creating your APS application, ' \
        'please ensure that the callback URL is set to: <strong>https://www.workato.com/oauth/callback</strong>.'
      },
      {
        name: 'client_secret',
        optional: false,
        control_type: 'password',
        hint: 'Enter the Client Secret from your APS application. ' \
        'Click <a href="https://tutorials.autodesk.io/#create-app-credentials">here</a> ' \
        'to learn how to generate Client Secret. When creating your APS application, ' \
        'please ensure that the callback URL is set to: <strong>https://www.workato.com/oauth/callback</strong>.'
      }
    ],
    authorization: {
      type: 'oauth2',
      authorization_url: lambda do |connection|
        scopes = 'user:read account:read data:write data:write data:read' \
        ' data:create account:write'
        'https://developer.api.autodesk.com/authentication/v2/authorize?' \
        'response_type=' \
        "code&client_id=#{connection['client_id']}&" \
        "scope=#{scopes}"
      end,

      acquire: lambda do |connection, auth_code, redirect_uri|
        response = post('https://developer.api.autodesk.com/authentication/' \
          'v2/token').
                   user(connection['client_id']).
                   password(connection['client_secret']).
                   payload(grant_type: 'authorization_code',
                           code: auth_code,
                           redirect_uri: redirect_uri).
                   request_format_www_form_urlencoded

        [response, nil, nil]
      end,

      refresh_on: [400, 401, 403],

      refresh: lambda do |connection, refresh_token|
        scopes = 'user:read account:read data:write data:write data:read' \
        ' data:create account:write'
        post('https://developer.api.autodesk.com/authentication/v2/' \
             'token').
                    user(connection['client_id']).
                    password(connection['client_secret']).
                    payload(grant_type: 'refresh_token',
                          refresh_token: refresh_token,
                          scope: scopes).
                    request_format_www_form_urlencoded

      end,
      apply: lambda do |_connection, access_token|
        if (current_url).include?('https://developer.api.autodesk.com')
          headers(Authorization: "Bearer #{access_token}", 'Content-Type': 'application/json')
        end
      end
    },
    base_uri: lambda do |_connection|
      'https://developer.api.autodesk.com'
    end
  },

  test: lambda do |_connection|
    get('/userprofile/v1/users/@me')
  end,

  methods: {
    # `get_sample_output` call not yet working
    get_sample_output: lambda do |input|
      # start case
      case input['object']
      when 'project'
        get("/project/v1/hubs/#{input['hub_id']}/projects?page[limit]=1")&.
        dig('data', 0)&.
        merge(hub_id: input['hub_id'], project_id: input['project_id'])

      when 'folder'
        get("/project/v1/hubs/#{input['hub_id']}/projects/#{input['project_id']}/topFolders")&.
        dig('data', 0)&.
        merge(hub_id: input['hub_id'], project_id: input['project_id'])

      when 'item'
        get("/data/v1/projects/#{input['project_id']}/folders/#{input['folder_id']}/search?page[limit]=1")&.
        dig('included', 0)&.
        merge(hub_id: input['hub_id'], project_id: input['project_id'])

      when 'cost'
        project_id = input['project_id'].split('.').last

        case input['cost_object']
        when 'change-order'
          get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/#{input['change_order_type']}?limit=1")&.
          dig('results', 0)&.
          merge(hub_id: input['hub_id'], project_id: input['project_id'])
        when 'payment'
          get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/?filter[associationType]=#{input['payment_type']}&limit=1")&.
          dig('results', 0)&.
          merge(hub_id: input['hub_id'], project_id: input['project_id'])
        else
          get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}?limit=1")&.
          dig('results')[0]&.
          merge(hub_id: input['hub_id'], project_id: input['project_id'])
        end
      end
      # end case
    end,

    format_cost_search: lambda do |input|
      if input.is_a?(Hash)
        input.each_with_object({}) do |(key, value), hash|
          if %w[
            lastModifiedSince
            rootId
            id
            externalSystem
            externalId
            code
            contractId
            mainContractId
            budgetStatus
            costStatus
            changeOrderId
            budgetId
            associationId
            associationType
            budgetPaymentId
          ].include?(key)
            hash["filter[#{key}]"] = value
          else
            hash[key] = value
          end
        end
      else
        input
      end
    end,

    format_rfi_search: lambda do |input|
      if input.is_a?(Hash)
        input.each_with_object({}) do |(key, value), hash|
          if %w[
            status
            createdAt
            dueDate
            search
            costImpact
            scheduleImpact
            priority
            discipline
            category
          ].include?(key)
            hash["filter[#{key}]"] = value
          else
            hash[key] = value
          end
        end
      else
        input
      end
    end,

    format_issue_search: lambda do |input|
      if input.is_a?(Hash)
        input.each_with_object({}) do |(key, value), hash|
          if %w[
            id
            issueTypeId
            issueSubtypeId
            status
            dueDate
            startDate
            published
            deleted
            createdAt
            createdBy
            openedAt
            updatedAt
            updatedBy
            assignedTo
            rootCauseId
            locationId
            subLocationId
            closedBy
            closedAt
            title
            displayId
            assignedToType
            customAttributes
          ].include?(key)
            hash["filter[#{key}]"] = value
          else
            hash[key] = value
          end
        end
      else
        input
      end
    end,

    format_output_response: lambda do |res, keys|
      keys.each do |key|
        res[key] = res[key]&.map { |value| { 'value' => value } } if res&.has_key?(key)
      end
    end,
    ##############################################################
    # Helper methods                                             #
    ##############################################################
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
          field[:name] = name
                         .gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        elsif (name = field['name'])
          field['label'] = field['label'].presence || name.labelize
          field['name'] = name
                          .gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
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
    end
  },

  object_definitions: {
    new_updated_object_input: {
      fields: lambda do |_connection, config_fields|
        case config_fields['object']
        when 'item'
          [
            {
              name: 'folder_id',
              label: 'Folder',
              control_type: 'tree',
              toggle_hint: 'Select folder',
              pick_list_params: { hub_id: 'hub_id', project_id: 'project_id' },
              tree_options: { selectable_folder: true },
              pick_list: :folders_list,
              optional: false,
              toggle_field: {
                name: 'folder_id',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Folder ID',
                toggle_hint: 'Enter folder ID'
              }
            },
            {
              name: 'subfolders',
              label: 'Include subfolders',
              control_type: 'select',
              optional: false,
              pick_list: [
                ['Yes', 'yes'],
                ['No', 'no']
              ]
            }
          ]
        when 'cost'
          [
            {
              name: 'cost_object',
              label: 'Cost object',
              control_type: 'select',
              toggle_hint: 'Select cost object type',
              pick_list: 'new_updated_cost_list',
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'cost_object',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Cost object type',
                toggle_hint: 'Enter cost object type',
              }
            }
          ].concat(
            case config_fields['cost_object']
            when 'change-order'
              [
                {
                  name: 'change_order_type',
                  label: 'Change order type',
                  control_type: 'select',
                  toggle_hint: 'Select change order type',
                  pick_list: 'change_order_list',
                  optional: false,
                  toggle_field: {
                    name: 'change_order_type',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Change order type',
                    toggle_hint: 'Enter change order type.',
                    hint: 'Possible values are: <strong>pco, rfq, rco, oco, sco</strong>.'
                  }
                }
              ]
            when 'payment'
              [
                {
                  name: 'payment_type',
                  label: 'Payment type',
                  control_type: 'select',
                  toggle_hint: 'Select payment type',
                  pick_list: [
                    ['Budget payment', 'MainContract'],
                    ['Cost payment', 'Contract']
                  ],
                  optional: false,
                  toggle_field: {
                    name: 'payment_type',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Payment type',
                    toggle_hint: 'Enter payment type',
                    hint: 'Possible values are: <strong>MainContract</strong> for budget payment and <strong>Contract</strong> for cost payment.'
                  }
                }
              ]
            else
              []
            end
          )
        when 'takeoff'
          [
            {
              name: 'takeoff_object',
              label: 'Takeoff object',
              control_type: 'select',
              toggle_hint: 'Select takeoff object type',
              pick_list: 'new_takeoff_list',
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'takeoff_object',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Takeoff object type',
                toggle_hint: 'Enter takeoff object type',
              }
            }
          ]
        when 'form'
          [
            {
              name: 'statuses',
              hint: 'Filter based on form status',
              type: 'string',
              control_type: :select,
              sticky: true,
              pick_list: [
                [ 'Draft', 'draft' ],
                [ 'Submitted', 'submitted' ],
                [ 'Archived', 'archived' ]
              ]
            }
          ]
        else
          []
        end
      end
    },

    new_event_input: {
      fields: lambda do |_connection, config_fields|
        [

          {
            name: 'folder_id',
            label: 'Folder',
            control_type: 'tree',
            toggle_hint: 'Select folder',
            pick_list_params: { hub_id: 'hub_id', project_id: 'project_id' },
            tree_options: { selectable_folder: true },
            pick_list: :folders_list,
            optional: false,
            change_on_blur: true,
            toggle_field: {
              name: 'folder_id',
              type: 'string',
              change_on_blur: true,
              control_type: 'text',
              label: 'Folder ID',
              toggle_hint: 'Enter folder ID'
            }
          },
          {
            name: 'filter',
            hint: 'JsonPath expression that can be used by you to filter the callbacks you receive.' \
                'More details can be found <a href="https://forge.autodesk.com/en/docs/webhooks/v1/developers_guide/callback-filtering/" target="_blank">here</a>.'
          },
          {
            name: 'hookAttribute',
            label: 'Hook attributes',
            control_type: 'key_value',
            # hint: 'Create custom attributes that will be returned with each event.',
            empty_list_title: 'Add hook attributes',
            empty_list_text: 'Create custom attributes that will be returned with each event.',
            type: 'array',
            of: 'object',
            'properties': [
              { name: 'key' },
              { name: 'value'}
            ]
          }
        ]
      end
    },

    create_object_input: {
      fields: lambda do |_connection, config_fields|
        case config_fields['object']
        when 'folder'
          [
            {
              name: 'folder_id',
              label: 'Parent folder',
              control_type: 'tree',
              toggle_hint: 'Select parent folder',
              pick_list_params: { hub_id: 'hub_id', project_id: 'project_id' },
              tree_options: { selectable_folder: true },
              pick_list: :folders_list,
              optional: false,
              toggle_field: {
                name: 'folder_id',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Parent folder ID',
                toggle_hint: 'Enter parent folder ID'
              }
            },
            {
              name: 'name',
              optional: false,
              hint: 'Folder names cannot contain the following characters: <, >, :, ", /, \, |, ?, *, `, \n, \r, \t, \0, \f, ¢, ™, $, ®.'
            }
          ]
        when 'cost'
          [
            {
              name: 'cost_object',
              label: 'Cost object',
              control_type: 'select',
              toggle_hint: 'Select cost object type',
              pick_list: 'create_cost_list',
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'cost_object',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Cost object type',
                toggle_hint: 'Enter cost object type',
              }
            }
          ].concat(
            case config_fields['cost_object']
            when 'attachment'
              [
                {
                  name: 'name',
                  optional: false,
                  hint: 'Name of the attachment. Max length: 255'
                },
                {
                  name: 'urn',
                  optional: false,
                  hint: 'Version URN from Autodesk Docs after the attachment is uploaded.'
                },
                {
                  name: 'associationId',
                  optional: false,
                  hint: 'The object ID of the item with which the actions are associated: ' \
                  'a budget, contract, or cost item for example.'
                },
                {
                  name: 'associationType',
                  optional: false,
                  control_type: 'select',
                  toggle_hint: 'Select association type',
                  pick_list: [
                    ['Budget', 'Budget'],
                    ['Budget payment', 'BudgetPayment'],
                    ['Contract', 'Contract'],
                    ['Cost item', 'CostItem'],
                    ['Cost payment', 'CostPayment'],
                    ['Expense', 'Expense'],
                    ['Expense item', 'ExpenseItem'],
                    ['Form instance', 'FormInstance'],
                    ['Main contract', 'MainContract'],
                    ['Payment', 'Payment'],
                    ['Payment item', 'PaymentItem']
                  ],
                  hint: 'The type of the item is associated to.',
                  toggle_field: {
                    name: 'associationType',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Association type',
                    toggle_hint: 'Enter association type',
                    hint: 'The type of the item is associated to.' \
                    'Possible values: <strong>Budget, Contract, FormInstance, CostItem, Payment, ' \
                    'MainContract, BudgetPayment, Expense, CostPayment, ExpenseItem, PaymentItem</strong>.'
                  }
                }
              ]
            when 'budget'
              [
                {
                  name: 'name',
                  optional: false,
                  hint: 'Name of the budget. Max length: 1024'
                },
                {
                  name: 'code',
                  optional: false,
                  hint: 'Unique code compliant with the budget code template defined by the project admin. Max length: 255'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'Detail description of the budget.'
                },
                {
                  name: 'parentId',
                  sticky: true,
                },
                {
                  name: 'quantity',
                  sticky: true,
                  type: 'number',
                  hint: 'Quantity of labor or material planned for a budget.',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'unitPrice',
                  sticky: true,
                  type: 'number',
                  hint: 'Unit price of a budget.',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'unit',
                  sticky: true,
                  hint: 'Unit of measures used in the budget.'
                },
                {
                  name: 'externalId',
                  sticky: true,
                  hint: 'The ID of the item in its original external system. ' \
                    'You can use this ID to track the source of truth, or to look up the data in an integrated system.'
                },
                {
                  name: 'externalSystem',
                  sticky: true,
                  hint: 'The name of the external system. You can use this name to ' \
                    'track the source of truth or to search in an integrated system.'
                },
                {
                  name: 'externalMessage',
                  sticky: true,
                  hint: 'A message that explains the sync status of the ' \
                    'ERP integration with the Autodesk Construction Cloud Cost module.'
                }
              ]
            when 'change-order'
              [
                {
                  name: 'change_order_type',
                  label: 'Change order type',
                  control_type: 'select',
                  toggle_hint: 'Select type',
                  pick_list: 'change_order_list',
                  optional: false,
                  extends_schema: true,
                  toggle_field: {
                    name: 'change_order_type',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Change order type',
                    toggle_hint: 'Enter type',
                    hint: 'Possible values are: <strong>pco, rfq, rco, oco, sco</strong>.'
                  }
                },
                {
                  name: 'name',
                  sticky: true,
                  hint: 'Name of the change order. Max length: 1024'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'Detailed description of the change order. Max length: 2048'
                },
                {
                  name: 'scope',
                  control_type: 'select',
                  toggle_hint: 'Select scope',
                  pick_list: [
                    ['Out', 'out'],
                    ['In', 'in'],
                    ['TBD', 'tbd'],
                    ['Contigency', 'contingency']
                  ],
                  sticky: true,
                  hint: 'Scope of the change order.',
                  toggle_field: {
                    name: 'change_order_type',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Scope',
                    toggle_hint: 'Enter scope',
                    hint: 'Possible values are: <strong>out, in, tbd, contingency</strong>.'
                  }
                },
                {
                  name: 'scopeOfWork',
                  sticky: true,
                  hint: 'Scope of work of the change order.'
                },
                {
                  name: 'note',
                  sticky: true,
                  hint: 'Additional notes to the change order.'
                },
                {
                  name: 'externalId',
                  sticky: true,
                  hint: 'The ID of the item in its original external system. ' \
                    'You can use this ID to track the source of truth, or to look up the data in an integrated system.'
                },
                {
                  name: 'externalSystem',
                  sticky: true,
                  hint: 'The name of the external system. You can use this name to ' \
                    'track the source of truth or to search in an integrated system.'
                },
                {
                  name: 'externalMessage',
                  sticky: true,
                  hint: 'A message that explains the sync status of the ' \
                    'ERP integration with the Autodesk Construction Cloud Cost module.'
                }
              ]
            when 'contract'
              [
                {
                  name: 'name',
                  optional: false,
                  hint: 'Name of the contract. Max length: 1024.'
                },
                {
                  name: 'code',
                  optional: false,
                  hint: 'Code of the contract. Max length: 255.'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'Detailed description of a contract. Max length: 2048.'
                },
                {
                  name: 'companyId',
                  sticky: true,
                  hint: 'The ID of a supplier company. This is the ID of a company managed by ACC Admin.'
                },
                {
                  name: 'type',
                  sticky: true,
                  hint: 'Type of the contract. For example, consultant or purchase order. ' \
                  'Type is customizable by the project admin.'
                },
                {
                  name: 'contactId',
                  sticky: true,
                  hint: 'Default contact of the supplier. This is the ID of a user managed by ACC Admin.'
                },
                {
                  name: 'signedBy',
                  sticky: true,
                  hint: 'The user who signed the contract. This is the ID of a company managed by ACC Admin.'
                },
                {
                  name: 'ownerId',
                  sticky: true,
                  hint: 'The user who is responsible the purchase. This is the ID of a company managed by ACC Admin.'
                },
                {
                  name: 'status',
                  sticky: true,
                  hint: 'The status of this contract.',
                  control_type: 'select',
                  toggle_hint: 'Select status',
                  pick_list: [
                    ['Draft', 'draft'],
                    ['Pending', 'pending'],
                    ['Submitted', 'submitted'],
                    ['Revise', 'revise'],
                    ['Sent', 'sent'],
                    ['Signed', 'signed'],
                    ['Executed', 'executed'],
                    ['Closed', 'closed']
                  ],
                  toggle_field: {
                    name: 'status',
                    type: 'string',
                    control_type: 'text',
                    change_on_blur: true,
                    label: 'Status',
                    toggle_hint: 'Enter status',
                    hint: 'The status of this contract. Possible values: ' \
                    '<strong>draft, pending, submitted, revise, sent, signed, executed, closed</strong>.'
                  }
                },
                {
                  name: 'externalId',
                  sticky: true,
                  hint: 'The ID of the item in its original external system. ' \
                  'You can use this ID to track the source of truth, or to look up the data in an integrated system.'
                },
                {
                  name: 'externalSystem',
                  sticky: true,
                  hint: 'The name of the external system. You can use this name ' \
                  'to track the source of truth or to search in an integrated system.'
                },
                {
                  name: 'externalMessage',
                  sticky: true,
                  hint: 'A message that explains the sync status of the ERP integration with the ACC Cost module.'
                }
              ]
            when 'cost-item'
              [
                {
                  name: 'name',
                  optional: false,
                  hint: 'Name of the cost item. Max length: 1024.'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'Detail description of the cost item. Max length: 2048'
                },
                {
                  name: 'changeOrderId',
                  sticky: true,
                  hint: 'The ID of the change order that the cost item is created in.'
                },
                {
                  name: 'budgetId',
                  sticky: true,
                  hint: 'The ID of the budget that the cost item is linked to.'
                },
                {
                  name: 'estimated',
                  sticky: true,
                  hint: 'Rough estimation of this item without a quotation.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'proposed',
                  sticky: true,
                  hint: 'Quoted cost of the cost item.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'submitted',
                  sticky: true,
                  hint: 'Amount sent to the owner for approval.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'approved',
                  sticky: true,
                  hint: 'Amount approved by the owner.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'committed',
                  sticky: true,
                  hint: 'Amount committed to the supplier.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'quantity',
                  sticky: true,
                  hint: 'The quantity of the cost item.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'unit',
                  sticky: true,
                  hint: 'The unit of the cost item.'
                }
              ]
            when 'expense'
              [
                {
                  name: 'name',
                  optional: false,
                  hint: 'Name of the expense. Max length 1024'
                },
                {
                  name: 'number',
                  sticky: true,
                  hint: 'Number of the expense. Max length 255'
                },
                {
                  name: 'supplierName',
                  optional: false,
                  hint: 'The supplier name for the expense.'
                },
                {
                  name: 'supplierId',
                  sticky: true,
                  hint: 'The supplier ID for the expense.'
                },
                {
                  name: 'budgetPaymentId',
                  sticky: true,
                  hint: 'The ID of the budget payment application to which the expense belongs.'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'The detail description of the expense. Max length 2048.'
                },
                {
                  name: 'note',
                  sticky: true,
                  hint: 'The note of the expense.'
                },
                {
                  name: 'term',
                  sticky: true,
                  hint: 'The term of the expense.'
                },
                {
                  name: 'referenceNumber',
                  sticky: true,
                  hint: 'The reference number of the expense.'
                },
                {
                  name: 'type',
                  sticky: true,
                  hint: 'The type of the expense. It is customizable by the project admin.'
                },
                {
                  name: 'scope',
                  sticky: true,
                  hint: 'The scope of the scope. Possible values: <strong>full, partial</strong>.'
                },
                {
                  name: 'purchaseBy',
                  sticky: true,
                  hint: 'The user who purchased items in the expense. This is the ID of a user managed in ACC Admin.'
                },
                {
                  name: 'status',
                  sticky: true,
                  hint: 'The status of the expense. Possible values: <strong>draft, pending, revise, ' \
                  'rejected, approved, paid</strong>.'
                },
                {
                  name: 'paymentDue',
                  sticky: true,
                  hint: 'The payment due date of the expense.',
                  type: 'date_time'
                },
                {
                  name: 'issuedAt',
                  sticky: true,
                  hint: 'The date and time when the expense is issued.',
                  type: 'date_time'
                },
                {
                  name: 'receivedAt',
                  sticky: true,
                  hint: 'The date and time when the expense is received.',
                  type: 'date_time'
                },
                {
                  name: 'paidAmount',
                  sticky: true,
                  hint: 'The actual amount when the expense is paid.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'paymentType',
                  sticky: true,
                  hint: 'The payment type, such as check or electronic transfer.'
                },
                {
                  name: 'paymentReference',
                  sticky: true,
                  hint: 'The check number or electronic transfer number.'
                },
                {
                  name: 'externalId',
                  sticky: true,
                  hint: 'The ID of the item in its original external system. ' \
                    'You can use this ID to track the source of truth, or to look up the data in an integrated system.'
                },
                {
                  name: 'externalSystem',
                  sticky: true,
                  hint: 'The name of the external system. You can use this name to ' \
                    'track the source of truth or to search in an integrated system.'
                },
                {
                  name: 'externalMessage',
                  sticky: true,
                  hint: 'A message that explains the sync status of the ' \
                    'ERP integration with the Autodesk Construction Cloud Cost module.'
                }
              ]
            when 'main-contract'
              [
                {
                  name: 'name',
                  sticky: true,
                  hint: 'Name of the main contract. Max length: 1024.'
                },
                {
                  name: 'code',
                  optional: false,
                  hint: 'Code of the main contract. Max length: 255.'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'Detailed description of the main contract. Max length: 2048.'
                },
                {
                  name: 'note',
                  sticky: true,
                  hint: 'The note for the main contract.'
                },
                {
                  name: 'scopeOfWork',
                  sticky: true,
                  hint: 'Scope of work for the main contract.'
                },
                {
                  name: 'type',
                  sticky: true,
                  hint: 'Type of the main contract. For example, consultant or purchase order. ' \
                  'Type is customizable by the project admin.'
                },
                {
                  name: 'startDate',
                  sticky: true,
                  hint: 'The start date for the main contract.',
                  type: 'date'
                },
                {
                  name: 'executedDate',
                  sticky: true,
                  hint: 'The date the main contract is executed.',
                  type: 'date'
                },
                {
                  name: 'plannedCompletionDate',
                  sticky: true,
                  hint: 'The planned completion date for the main contract.',
                  type: 'date'
                },
                {
                  name: 'actualCompletionDate',
                  sticky: true,
                  hint: 'The actual completion date for the main contract.',
                  type: 'date'
                },
                {
                  name: 'closeDate',
                  sticky: true,
                  hint: 'The actual completion date for the main contract.',
                  type: 'date'
                },
                {
                  name: 'status',
                  sticky: true,
                  hint: 'The status of this contract.',
                  control_type: 'select',
                  toggle_hint: 'Select status',
                  pick_list: [
                    ['Closed', 'closed'],
                    ['Executed', 'executed'],
                    ['Review', 'review'],
                    ['Signed', 'signed']
                  ],
                  toggle_field: {
                    name: 'status',
                    type: 'string',
                    control_type: 'text',
                    change_on_blur: true,
                    label: 'Status',
                    toggle_hint: 'Enter status',
                    hint: 'The status of this contract. Possible values: ' \
                    '<strong>closed, executed, review, signed</strong>.'
                  }
                },
                {
                  name: 'externalId',
                  sticky: true,
                  hint: 'The ID of the item in its original external system. ' \
                  'You can use this ID to track the source of truth, or to look up the data in an integrated system.'
                },
                {
                  name: 'externalSystem',
                  sticky: true,
                  hint: 'The name of the external system. You can use this name ' \
                  'to track the source of truth or to search in an integrated system.'
                },
                {
                  name: 'externalMessage',
                  sticky: true,
                  hint: 'A message that explains the sync status of the ERP integration with the ACC Cost module.'
                }
              ]
            when 'time-sheet'
              [
                {
                  name: 'trackingItemInstanceId',
                  label: 'Tracking item instance ID',
                  hint: 'The ID of the tracking item instance the time sheet is logged against.',
                  optional: false
                },
                {
                  name: 'startDate',
                  hint: 'The start day of the time sheet.',
                  type: 'date',
                  sticky: true
                },
                {
                  name: 'endDate',
                  hint: 'The end day of the time sheet.',
                  type: 'date',
                  optional: false
                },
                {
                  name: 'inputQuantity',
                  label: 'Tracked input quantity',
                  hint: 'The input unit of the time sheet, now only hour(hr).',
                  type: 'integer',
                  convert_input: 'integer_conversion',
                  optional: false
                },
                {
                  name: 'outputQuantity',
                  label: 'Tracked output quantity',
                  hint: 'The output quantity logged in this time sheet.',
                  type: 'integer',
                  convert_input: 'integer_conversion',
                  optional: false
                }
              ]
            else
              []
            end
          )
        when 'issue'
          [
            {
              name: 'published',
              sticky: true,
              type: 'boolean',
              control_type: 'select',
              toggle_hint: 'Select published status',
              convert_input: 'boolean_conversion',
              pick_list: [
                ['Yes', true],
                ['No', false]
              ],
              sticky: true,
              toggle_field: {
                name: 'published',
                type: 'string',
                control_type: 'text',
                label: 'Published status',
                change_on_blur: true,
                toggle_hint: 'Enter published status',
                hint: 'States whether the issue is published. Default value: false (e.g. unpublished).'
              }
            },
            {
              name: 'issueTypeId',
              label: 'Issue type',
              control_type: 'select',
              toggle_hint: 'Select issue type',
              pick_list: 'search_issue_type',
              pick_list_params: { project_id: 'project_id' },
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'issueTypeId',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Issue type ID',
                toggle_hint: 'Enter issue type ID',
                hint: 'Filter issues by the unique identifier of the type of the issue. Separate multiple values with commas.'
              }
            },
            {
              name: 'issueSubtypeId',
              label: 'Issue sub type',
              control_type: 'select',
              toggle_hint: 'Select issue sub type',
              pick_list: 'search_issue_sub_type',
              pick_list_params: { project_id: 'project_id', issue_type_id: 'issueTypeId' },
              optional: false,
              toggle_field: {
                name: 'issueSubtypeId',
                type: 'string',
                control_type: 'text',
                change_on_blur: true,
                label: 'Issue sub type ID',
                toggle_hint: 'Enter issue subtype ID',
                hint: 'Filter issues by the unique identifier of the subtype of the issue. Separate multiple values with commas.'
              }
            },
            {
              name: 'title',
              optional: false,
              hint: 'The title of the Issue. Max length: 4200.'
            },
            {
              name: 'description',
              hint: 'The description of the purpose of the issue. Max length: 10000.',
              sticky: true
            },
            {
              name: 'status',optional: false, control_type: 'select',
              pick_list: %w[pending open].map { |option| [option.labelize, option] },
              toggle_hint: 'Select status',
              sticky: true,
              toggle_field: {
                name: 'status',
                type: 'string',
                control_type: 'text',
                toggle_hint: 'Enter status value',
                hint: 'The status of the issue. Possible values: <b>pending</b>, <b>open</b>. The default is <b>pending</b>.'
              }
            },
            {
              name: 'startDate',
              label: 'Start Date',
              type: 'date',
              sticky: true
            },
            {
              name: 'dueDate',
              label: 'Due Date',
              type: 'date',
              sticky: true
            },
            {
              name: 'locationId',
              label: 'Location ID',
              hint: 'The UUID of the location',
              sticky: true
            },
            {
              name: 'locationDetails',
              label: 'Location Details',
              hint: 'Free form field for location details, accepts a string value',
              sticky: true
            },
            {
              name: 'assignedTo',
              label: 'Assigned to',
              hint: 'The Autodesk ID (uid) of the user you want to assign to this issue. If you specify this attribute you need to also specify Assigned to type.',
              sticky: true
            },
            {
              name: 'assignedToType',
              sticky: true,
              control_type: 'select',
              toggle_hint: 'Select assignee type',
              extends_schema: true,
              pick_list: [
                ['Company', 'company'],
                ['Role', 'role'],
                ['User', 'user']
              ],
              sticky: true,
              toggle_field: {
                name: 'assignedToType',
                type: 'string',
                control_type: 'text',
                label: 'Assignee type',
                change_on_blur: true,
                toggle_hint: 'Enter assignee type',
                hint: 'Filter issues by the type of the current assignee of this issue. Separate multiple values with commas. Possible values: user, company, role'
              }
            },
            {
              name: 'ownerId',
              label: 'Owner ID',
              hint: 'The Autodesk ID (uid) of the user who owns this issue.',
              sticky: true
            },
            {
              name: 'rootCauseId',
              label: 'Root Cause ID',
              hint: 'The ID of the type of root cause for this issue.',
              sticky: true
            },
            {
              name: 'watchers',
              label: 'Watchers',
              hint: 'An Autodesk ID based list of watchers for the issue.',
              sticky: true
            }
          ]
        when 'rfi'
          [
            {
              name: 'title',
              optional: false,
              hint: 'The title of the RFI.'
            },
            {
              name: 'question',
              sticky: true,
              hint: 'The RFI question.'
            },
            {
              name: 'suggestedAnswer',
              sticky: true,
              hint: 'The suggested answer for the RFI.'
            },
            {
              name: 'location',
              sticky: true,
              type: 'object',
              properties: [
                {
                  name: 'description',
                  sticky: true,
                  hint: 'A description of the location of the RFI in the construction project.'
                }
              ]
            },
            {
              name: 'assignedTo',
              sticky: true,
              hint: 'The Autodesk ID of the assigned user.'
            },
            {
              name: 'dueDate',
              sticky: true,
              type: 'date_time',
              hint: 'The timestamp of the due date for the RFI'
            },
            {
              name: 'costImpact',
              sticky: true,
              hint: 'The cost impact status of the RFI.',
              control_type: 'select',
              pick_list: [
                ['Yes', 'Yes'],
                ['No', 'No'],
                ['Unknown', 'Unknown']
              ],
              toggle_hint: 'Select cost impact',
              toggle_field: {
                name: 'scheduleImpact',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Cost impact',
                toggle_hint: 'Enter cost impact',
                hint: 'The cost impact status of the RFI. Possible values: ' \
              '<strong>Yes, No, Unknown</strong> or leave empty.'
              }
            },
            {
              name: 'scheduleImpact',
              sticky: true,
              hint: 'The schedule impact status of the RFI.',
              control_type: 'select',
              pick_list: [
                ['Yes', 'Yes'],
                ['No', 'No'],
                ['Unknown', 'Unknown']
              ],
              toggle_hint: 'Select schedule impact',
              toggle_field: {
                name: 'scheduleImpact',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Schedule impact',
                toggle_hint: 'Enter schedule impact',
                hint: 'The schedule impact status of the RFI. Possible values: ' \
                '<strong>Yes, No, Unknown</strong> or leave empty.'
              }
            },
            {
              name: 'priority',
              sticky: true,
              control_type: 'select',
              pick_list: [
                ['High', 'High'],
                ['Normal', 'Normal'],
                ['Low', 'Low']
              ],
              hint: 'The priority status of the RFI.',
              toggle_hint: 'Select priority',
              toggle_field: {
                name: 'priority',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Priority',
                toggle_hint: 'Enter priority',
                hint: 'The priority status of the RFI. Possible values: ' \
                '<strong>High, Normal, Low</strong> or leave empty.'
              }
            },
            {
              name: 'discipline',
              sticky: true,
              hint: 'The disciplines of the RFI.',
              control_type: 'multiselect',
              delimiter: ',',
              pick_list: [
                ['Architectural', 'Architectural'],
                ['Civil/Site', 'Civil/Site'],
                ['Concrete', 'Concrete'],
                ['Electrical', 'Electrical'],
                ['Exterior Envelope', 'Exterior Envelope'],
                ['Fire Protection', 'Fire Protection'],
                ['Interior/Finishes', 'Interior/Finishes'],
                ['Landscaping', 'Landscaping'],
                ['Masonry', 'Masonry'],
                ['Mechanical', 'Mechanical'],
                ['Plumbing', 'Plumbing'],
                ['Structural', 'Structural'],
                ['Other', 'Other']
              ],
              toggle_hint: 'Select disciplines',
              toggle_field: {
                name: 'discipline',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Discipline',
                toggle_hint: 'Enter disciplines',
                hint: 'The disciplines of the RFI. Separate each discipline with a comma.'
              }
            },
            {
              name: 'category',
              sticky: true,
              hint: 'The categories of the RFI.',
              control_type: 'multiselect',
              delimiter: ',',
              pick_list: [
                ['Code Compliance', 'Code Compliance'],
                ['Constructability', 'Constructability'],
                ['Design Coordination', 'Design Coordination'],
                ['Documentation Conflict', 'Documentation Conflict'],
                ['Documentation Incomplete', 'Documentation Incomplete'],
                ['Field condition', 'Field condition'],
                ['Other', 'Other']
              ],
              toggle_hint: 'Select categories',
              toggle_field: {
                name: 'category',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Category',
                toggle_hint: 'Enter categories',
                hint: 'The categories of the RFI. Separate each category with a comma.'
              }
            },
            {
              name: 'reference',
              sticky: true,
              hint: 'An external ID; typically used when the RFI was created in another system.' \
              'Max length: 20 characters.'
            },
            {
              name: 'coReviewers',
              sticky: true,
              hint: 'Add members who can contribute to the RFI response. Separate each Autodesk ID with a comma.'
            },
            {
              name: 'distributionList',
              sticky: true,
              hint: 'Add members to receive email notifications when the RFI is updated.  ' \
              'Separate each Autodesk ID with a comma.'
            }
          ]
        when 'rfi_comment'
          [
            {
              name: 'id',
              label: 'RFI ID',
              optional: false
            },
            {
              name: 'body',
              hint: 'The content of teh comment. Max length: 1,000 characters.',
              optional: false
            }
          ]
        when 'webhook'
          [
            {
              name: 'folder_id',
              label: 'Folder',
              control_type: 'tree',
              toggle_hint: 'Select folder',
              pick_list_params: { hub_id: 'hub_id', project_id: 'project_id' },
              tree_options: { selectable_folder: true },
              pick_list: :folders_list,
              optional: false,
              change_on_blur: true,
              toggle_field: {
                name: 'folder_id',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Folder ID',
                toggle_hint: 'Enter folder ID'
              }
            },
            {
              name: 'event',
              optional: false,
              control_type: 'select',
              options: [
                [ 'New or updated version of an item', 'dm.version.added' ],
                [ 'New or updated properties of an item', 'dm.version.modified' ],
                [ 'Deleted item', 'dm.version.deleted' ],
                [ 'New folder', 'dm.folder.added' ],
                [ 'Modified folder', 'dm.folder.modified' ],
                [ 'Deleted folder', 'dm.folder.deleted' ]
              ],
              toggle_hint: 'Select event',
              toggle_field: {
                name: 'event',
                type: 'string',
                control_type: 'text',
                label: 'Event name',
                toggle_hint: 'Enter event',
                hint: 'Refer to list of events <a href="https://forge.autodesk.com/en/docs/webhooks/v1/reference/events/data_management_events/" target="_blank">here</a>.'
              }
            },
            {
              name: 'callbackUrl',
              optional: false,
              control_type: 'url',
              hint: 'Callback URL registered for this webhook. All events from the webhook will be sent to this URL.'
            },
            {
              name: 'filter',
              hint: 'JsonPath expression that can be used by you to filter the callbacks you receive.' \
                  'More details can be found <a href="https://forge.autodesk.com/en/docs/webhooks/v1/developers_guide/callback-filtering/" target="_blank">here</a>.'
            },
            {
              name: 'hookExpiry',
              type: 'date_time',
              hint: 'Date and time when the hook should expire and automatically be deleted. Not providing this parameter means the hook never expires.'
            },
            {
              name: 'hookAttribute',
              label: 'Hook attributes',
              control_type: 'key_value',
              empty_list_title: 'Add hook attributes',
              empty_list_text: 'Create custom attributes that will be returned with each event.',
              type: 'array',
              of: 'object',
              'properties': [
                { name: 'key' },
                { name: 'value'}
              ]
            }
          ]
        else
          []
        end
      end
    },

    update_object_input: {
      fields: lambda do |_connection, config_fields|
        case config_fields['object']
        when 'item'
          [
            {
              name: 'folder_id',
              label: 'Folder',
              control_type: 'tree',
              hint: 'Select folder',
              toggle_hint: 'Select folder',
              pick_list_params: { hub_id: 'hub_id', project_id: 'project_id' },
              tree_options: { selectable_folder: true },
              pick_list: :folders_list,
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'folder_id',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Folder ID',
                toggle_hint: 'Enter folder ID',
                hint: 'Get ID from url of the folder page.'
              }
            },
            {
              name: 'item_id',
              label: 'File name',
              control_type: 'tree',
              hint: 'Select file',
              toggle_hint: 'Select file',
              pick_list: :folder_items,
              pick_list_params: { project_id: 'project_id', folder_id: 'folder_id' },
              optional: false,
              toggle_field: {
                name: 'item_id',
                type: 'string',
                control_type: 'text',
                change_on_blur: true,
                label: 'File ID',
                toggle_hint: 'Enter file ID',
                hint: 'Provide file ID.'
              }
            },
            {
              name: 'name',
              optional: false,
              hint: 'The name of the file (1-255 characters). Reserved characters: <, >, :, ", /, \, |, ?, *, `, \n, \r, \t, \0, \f, ¢, ™, $, ®. This must be the same as included[i].attributes.name.'
            }
          ]
        when 'folder'
          [
            {
              name: 'folder_id',
              label: 'Folder',
              control_type: 'tree',
              hint: 'Select folder',
              toggle_hint: 'Select folder',
              pick_list_params: { hub_id: 'hub_id', project_id: 'project_id' },
              tree_options: { selectable_folder: true },
              pick_list: :folders_list,
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'folder_id',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Folder ID',
                toggle_hint: 'Enter folder ID',
                hint: 'Get ID from url of the folder page.'
              }
            },
            {
              name: 'name',
              optional: false,
              hint: 'Folder names cannot contain the following characters: <, >, :, ", /, \, |, ?, *, `, \n, \r, \t, \0, \f, ¢, ™, $, ®.'
            }
          ]
        when 'cost'
          [
            {
              name: 'cost_object',
              label: 'Cost object',
              control_type: 'select',
              toggle_hint: 'Select cost object type',
              pick_list: 'update_cost_list',
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'cost_object',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Cost object type',
                toggle_hint: 'Enter cost object type',
              }
            }
          ].concat(
            case config_fields['cost_object']
            when 'budget'
              [
                {
                  name: 'name',
                  sticky: true,
                  hint: 'Name of the budget. Max length: 1024'
                },
                {
                  name: 'code',
                  sticky: true,
                  hint: 'Unique code compliant with the budget code template defined by the project admin. ' \
                  'Max length: 255'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'Unique code compliant with the budget code template defined by the project admin. ' \
                  'Max length: 255'
                },
                {
                  name: 'quantity',
                  sticky: true,
                  type: 'number',
                  hint: 'Quantity of labor or material planned for a budget.',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'unitPrice',
                  sticky: true,
                  type: 'number',
                  hint: 'Unit price of a budget.',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'unit',
                  sticky: true,
                  hint: 'Unit of measures used in the budget.'
                },
                {
                  name: 'quantity',
                  sticky: true,
                  type: 'number',
                  hint: 'Quantity of labor or material planned for a budget.',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'actualQuantity',
                  sticky: true,
                  type: 'number',
                  hint: 'Actual quantity of labor or material planned for a budget.',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'actualUnitPrice',
                  sticky: true,
                  type: 'number',
                  hint: 'Actual unit price of a budget.',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'actualCost',
                  sticky: true,
                  type: 'number',
                  hint: 'Total amount of actual cost of the budget.',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'adjustments',
                  sticky: true,
                  hint: 'The adjustment object. The forecast adjustments made to projected' \
                  ' costs to reflect anticipated final costs.',
                  type: 'object',
                  properties: [
                    { name: 'detail', hint: 'The list of adjustments.',
                      type: 'array', of: 'object', properties: [
                        {
                          name: 'quantity',
                          sticky: true,
                          type: 'number',
                          hint: 'The quantity of items for the adjustment.',
                          render_input: 'float_conversion',
                          parse_output: 'float_conversion'
                        },
                        {
                          name: 'unitPrice',
                          sticky: true,
                          type: 'number',
                          hint: 'The price of the adjustment.',
                          render_input: 'float_conversion',
                          parse_output: 'float_conversion'
                        },
                        {
                          name: 'unit',
                          sticky: true,
                          hint: 'The unit of measure for the adjustment.'
                        }
                      ]
                    }
                  ]
                },
                {
                  name: 'lockedField',
                  sticky: true,
                  hint: 'The locked budget item field. You can lock the budget item’s ' \
                  'amount (<strong>originalAmount</strong>), quantity (quantity), or ' \
                  'unit cost (<strong>unitPrice</strong>) when calculating a budget.'
                }
              ]
            when 'change-order'
              [
                {
                  name: 'change_order_type',
                  label: 'Change order type',
                  control_type: 'select',
                  toggle_hint: 'Select type',
                  pick_list: 'change_order_list',
                  optional: false,
                  toggle_field: {
                    name: 'change_order_type',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Change order type',
                    toggle_hint: 'Enter type',
                    hint: 'Possible values are: <strong>pco, rfq, rco, oco, sco</strong>.'
                  }
                },
                {
                  name: 'name',
                  sticky: true,
                  hint: 'Name of the change order. Max length: 1024'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'Detailed description of the change order. Max length: 2048'
                },
                {
                  name: 'scope',
                  control_type: 'select',
                  toggle_hint: 'Select scope',
                  pick_list: [
                    ['Out', 'out'],
                    ['In', 'in'],
                    ['TBD', 'tbd'],
                    ['Contigency', 'contingency']
                  ],
                  sticky: true,
                  hint: 'Scope of the change order.',
                  toggle_field: {
                    name: 'change_order_type',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Scope',
                    toggle_hint: 'Enter scope',
                    hint: 'Possible values are: <strong>out, in, tbd, contingency</strong>.'
                  }
                },
                {
                  name: 'scopeOfWork',
                  sticky: true,
                  hint: 'Scope of work of the change order.'
                },
                {
                  name: 'note',
                  sticky: true,
                  hint: 'Additional notes to the change order.'
                },
                {
                  name: 'ownerId',
                  sticky: true,
                  hint: 'The ID of the change order’s owner/purchaser, a project user managed by ACC Admin.'
                },
                {
                  name: 'recipients',
                  sticky: true,
                  hint: 'Persons that the generated documents will be sent to.',
                  type: 'array', of: 'object', properties: [
                    {
                      name: 'id',
                      sticky: true,
                      hint: 'This is the ID of a user managed by ACC Admin.'
                    },
                    {
                      name: 'isDefault',
                      sticky: true,
                      type: 'boolean',
                      hint: 'True if this is the default recipient the change order.'
                    }
                  ]
                }
              ]
            when 'contract'
              [
                {
                  name: 'name',
                  sticky: true,
                  hint: 'Name of the contract. Max length: 1024.'
                },
                {
                  name: 'code',
                  sticky: true,
                  hint: 'Code of the contract. Max length: 255.'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'Detailed description of a contract. Max length: 2048.'
                },
                {
                  name: 'companyId',
                  sticky: true,
                  hint: 'The ID of a supplier company. This is the ID of a company managed by ACC Admin.'
                },
                {
                  name: 'type',
                  sticky: true,
                  hint: 'Type of the contract. For example, consultant or purchase order. ' \
                  'Type is customizable by the project admin.'
                },
                {
                  name: 'contactId',
                  sticky: true,
                  hint: 'Default contact of the supplier. This is the ID of a user managed by ACC Admin.'
                },
                {
                  name: 'signedBy',
                  sticky: true,
                  hint: 'The user who signed the contract. This is the ID of a company managed by ACC Admin.'
                },
                {
                  name: 'ownerId',
                  sticky: true,
                  hint: 'The user who is responsible the purchase. This is the ID of a company managed by ACC Admin.'
                },
                {
                  name: 'status',
                  sticky: true,
                  hint: 'The status of this contract.',
                  control_type: 'select',
                  toggle_hint: 'Select status',
                  pick_list: [
                    ['Draft', 'draft'],
                    ['Pending', 'pending'],
                    ['Submitted', 'submitted'],
                    ['Revise', 'revise'],
                    ['Sent', 'sent'],
                    ['Signed', 'signed'],
                    ['Executed', 'executed'],
                    ['Closed', 'closed']
                  ],
                  toggle_field: {
                    name: 'status',
                    type: 'string',
                    control_type: 'text',
                    change_on_blur: true,
                    label: 'Status',
                    toggle_hint: 'Enter status',
                    hint: 'The status of this contract. Possible values: ' \
                    '<strong>draft, pending, submitted, revise, sent, signed, executed, closed</strong>.'
                  }
                }
              ]
            when 'cost-item'
              [
                {
                  name: 'name',
                  sticky: true,
                  hint: 'Name of the cost item. Max length: 1024.'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'Detail description of the cost item. Max length: 2048'
                },
                {
                  name: 'type',
                  sticky: true,
                  hint: 'The type of the cost item. It is customizable by the project admin.'
                },
                {
                  name: 'budgetId',
                  sticky: true,
                  hint: 'The ID of the budget that the cost item is linked to.'
                },
                {
                  name: 'contractId',
                  sticky: true,
                  hint: 'The ID of the contract that the cost item is linked to.'
                },
                {
                  name: 'estimated',
                  sticky: true,
                  hint: 'Rough estimation of this item without a quotation.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'proposed',
                  sticky: true,
                  hint: 'Quoted cost of the cost item.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'submitted',
                  sticky: true,
                  hint: 'Amount sent to the owner for approval.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'approved',
                  sticky: true,
                  hint: 'Amount approved by the owner.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'committed',
                  sticky: true,
                  hint: 'Amount committed to the supplier.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'quantity',
                  sticky: true,
                  hint: 'The quantity of the cost item.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'unit',
                  sticky: true,
                  hint: 'The unit of the cost item.'
                }
              ]
            when 'expense'
              [
                {
                  name: 'name',
                  sticky: true,
                  hint: 'Name of the expense. Max length 1024'
                },
                {
                  name: 'number',
                  sticky: true,
                  hint: 'Number of the expense. Max length 255'
                },
                {
                  name: 'supplierName',
                  sticky: true,
                  hint: 'The supplier name for the expense.'
                },
                {
                  name: 'supplierId',
                  sticky: true,
                  hint: 'The supplier ID for the expense.'
                },
                {
                  name: 'budgetPaymentId',
                  sticky: true,
                  hint: 'The ID of the budget payment application to which the expense belongs.'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'The detail description of the expense. Max length 2048.'
                },
                {
                  name: 'note',
                  sticky: true,
                  hint: 'The note of the expense.'
                },
                {
                  name: 'term',
                  sticky: true,
                  hint: 'The term of the expense.'
                },
                {
                  name: 'referenceNumber',
                  sticky: true,
                  hint: 'The reference number of the expense.'
                },
                {
                  name: 'type',
                  sticky: true,
                  hint: 'The type of the expense. It is customizable by the project admin.'
                },
                {
                  name: 'scope',
                  sticky: true,
                  hint: 'The scope of the scope. Possible values: <strong>full, partial</strong>.'
                },
                {
                  name: 'purchaseBy',
                  sticky: true,
                  hint: 'The user who purchased items in the expense. This is the ID of a user managed in ACC Admin.'
                },
                {
                  name: 'status',
                  sticky: true,
                  hint: 'The status of the expense. Possible values: <strong>draft, pending, revise, ' \
                  'rejected, approved, paid</strong>.'
                },
                {
                  name: 'paymentDue',
                  sticky: true,
                  hint: 'The payment due date of the expense.',
                  type: 'date_time'
                },
                {
                  name: 'issuedAt',
                  sticky: true,
                  hint: 'The date and time when the expense is issued.',
                  type: 'date_time'
                },
                {
                  name: 'receivedAt',
                  sticky: true,
                  hint: 'The date and time when the expense is received.',
                  type: 'date_time'
                },
                {
                  name: 'paidAmount',
                  sticky: true,
                  hint: 'The actual amount when the expense is paid.',
                  type: 'number',
                  render_input: 'float_conversion',
                  parse_output: 'float_conversion'
                },
                {
                  name: 'paymentType',
                  sticky: true,
                  hint: 'The payment type, such as check or electronic transfer.'
                },
                {
                  name: 'paymentReference',
                  sticky: true,
                  hint: 'The check number or electronic transfer number.'
                },
                {
                  name: 'externalId',
                  sticky: true,
                  hint: 'The ID of the item in its original external system. ' \
                    'You can use this ID to track the source of truth, or to look up the data in an integrated system.'
                },
                {
                  name: 'externalSystem',
                  sticky: true,
                  hint: 'The name of the external system. You can use this name to ' \
                    'track the source of truth or to search in an integrated system.'
                },
                {
                  name: 'externalMessage',
                  sticky: true,
                  hint: 'A message that explains the sync status of the ' \
                    'ERP integration with the Autodesk Construction Cloud Cost module.'
                }
              ]
            when 'main-contract'
              [
                {
                  name: 'name',
                  sticky: true,
                  hint: 'Name of the main contract. Max length: 1024.'
                },
                {
                  name: 'code',
                  sticky: true,
                  hint: 'Code of the main contract. Max length: 255.'
                },
                {
                  name: 'description',
                  sticky: true,
                  hint: 'Detailed description of the main contract. Max length: 2048.'
                },
                {
                  name: 'note',
                  sticky: true,
                  hint: 'The note for the main contract.'
                },
                {
                  name: 'scopeOfWork',
                  sticky: true,
                  hint: 'Scope of work for the main contract.'
                },
                {
                  name: 'type',
                  sticky: true,
                  hint: 'Type of the main contract. For example, consultant or purchase order. ' \
                  'Type is customizable by the project admin.'
                },
                {
                  name: 'startDate',
                  sticky: true,
                  hint: 'The start date for the main contract.',
                  type: 'date'
                },
                {
                  name: 'executedDate',
                  sticky: true,
                  hint: 'The date the main contract is executed.',
                  type: 'date'
                },
                {
                  name: 'plannedCompletionDate',
                  sticky: true,
                  hint: 'The planned completion date for the main contract.',
                  type: 'date'
                },
                {
                  name: 'actualCompletionDate',
                  sticky: true,
                  hint: 'The actual completion date for the main contract.',
                  type: 'date'
                },
                {
                  name: 'closeDate',
                  sticky: true,
                  hint: 'The actual completion date for the main contract.',
                  type: 'date'
                },
                {
                  name: 'status',
                  sticky: true,
                  hint: 'The status of this contract.',
                  control_type: 'select',
                  toggle_hint: 'Select status',
                  pick_list: [
                    ['Closed', 'closed'],
                    ['Executed', 'executed'],
                    ['Review', 'review'],
                    ['Signed', 'signed']
                  ],
                  toggle_field: {
                    name: 'status',
                    type: 'string',
                    control_type: 'text',
                    change_on_blur: true,
                    label: 'Status',
                    toggle_hint: 'Enter status',
                    hint: 'The status of this contract. Possible values: ' \
                    '<strong>closed, executed, review, signed</strong>.'
                  }
                },
                {
                  name: 'externalId',
                  sticky: true,
                  hint: 'The ID of the item in its original external system. ' \
                  'You can use this ID to track the source of truth, or to look up the data in an integrated system.'
                },
                {
                  name: 'externalSystem',
                  sticky: true,
                  hint: 'The name of the external system. You can use this name ' \
                  'to track the source of truth or to search in an integrated system.'
                },
                {
                  name: 'externalMessage',
                  sticky: true,
                  hint: 'A message that explains the sync status of the ERP integration with the ACC Cost module.'
                }
              ]
            when 'time-sheet'
              [
                {
                  name: 'inputQuantity',
                  label: 'Tracked input quantity (hr)',
                  hint: 'The input unit of the time sheet, now only hour(hr).',
                  type: 'integer',
                  convert_input: 'integer_conversion',
                  sticky: true
                },
                {
                  name: 'outputQuantity',
                  label: 'Tracked output quantity (ea)',
                  hint: 'The output quantity logged in this time sheet.',
                  type: 'integer',
                  convert_input: 'integer_conversion',
                  sticky: true
                }
              ]
            else
              []
            end
          ).concat(
            [
              {
              name: 'id',
              label: 'Object ID',
              optional: false,
              hint: 'The ID of the object to update.'
              }
            ]
          )
        when 'issue'
          [
            {
              name: 'id',
              optional: false,
              label: 'Issue ID',
              hint: 'The ID of the Issue to update.'
            },
            {
              name: 'title',
              sticky: true,
              hint: 'The new title of the Issue.'
            },
            {
              name: 'status',
              control_type: 'select',
              sticky: true,
              pick_list: %w[pending open in_review closed].map { |option| [option.labelize, option] },
                toggle_hint: 'Select status',
                  toggle_field: {
                    name: 'status',
                    label: 'Status',
                    type: 'string',
                    control_type: 'text',
                    toggle_hint: 'Enter status value',
                    hint: 'The current status of the issue. Possible values: <b>open</b>, <b>pending</b>, <b>in_review</b>, <b>closed</b>.'
                  }
            },
            {
              name: 'description',
              hint: 'The description of the purpose of the issue.',
              sticky: true
            },
            {
              name: 'dueDate',
              label: 'Due Date',
              type: 'date',
              sticky: true
            },
            {
              name: 'startDate',
              label: 'Start Date',
              type: 'date',
              sticky: true
            },
            {
              name: 'rootCauseId',
              label: 'Root Cause ID',
              hint: 'The ID of the type of root cause for this issue.',
              sticky: true
            },
            {
              name: 'locationId',
              label: 'Location ID',
              hint: 'The UUID of the location',
              sticky: true
            },
            {
              name: 'locationDetails',
              label: 'Location Details',
              hint: 'Free form field for location details, accepts a string value',
              sticky: true
            },
            {
              name: 'assignedTo',
              label: 'Assigned to',
              hint: 'The Autodesk ID (uid) of the user you want to assign to this issue. If you specify this attribute you need to also specify Assigned to type.',
              sticky: true
            },
            {
              name: 'assignedToType',
              sticky: true,
              control_type: 'select',
              toggle_hint: 'Select assignee type',
              extends_schema: true,
              pick_list: [
                ['Company', 'company'],
                ['Role', 'role'],
                ['User', 'user']
              ],
              sticky: true,
              toggle_field: {
                name: 'assignedToType',
                type: 'string',
                control_type: 'text',
                label: 'Assignee type',
                change_on_blur: true,
                toggle_hint: 'Enter assignee type',
                hint: 'Filter issues by the type of the current assignee of this issue. Separate multiple values with commas. Possible values: user, company, role'
              }
            },
            {
              name: 'ownerId',
              label: 'Owner ID',
              hint: 'The Autodesk ID (uid) of the user who owns this issue.',
              sticky: true
            },
            {
              name: 'watchers',
              label: 'Watchers',
              hint: 'An Autodesk ID based list of watchers for the issue.',
              sticky: true
            }
          ]
        when 'rfi'
          [
            {
              name: 'id',
              optional: false,
              label: 'RFI ID',
              hint: 'The ID of the RFI to update.'
            },
            {
              name: 'title',
              sticky: true,
              hint: 'The title of the RFI.'
            },
            {
              name: 'status',
              sticky: true,
              hint: 'The status of the RFI.',
              control_type: 'select',
              pick_list: [
                ['Draft', 'draft'],
                ['Open', 'open'],
                ['Submitted', 'submitted'],
                ['Answered', 'answered'],
                ['Rejected', 'rejected'],
                ['Closed', 'closed'],
                ['Void', 'void']
              ],
              toggle_hint: 'Select status',
              toggle_field: {
                name: 'status',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Status',
                toggle_hint: 'Enter status',
                hint: 'The status of the RFI. Possible values: ' \
              '<strong>draft, open, submitted, answered, rejected, closed, void</strong>.'
              }
            },
            {
              name: 'question',
              sticky: true,
              hint: 'The RFI question.'
            },
            {
              name: 'officialResponse',
              sticky: true,
              hint: 'The official response to the RFI.'
            },
            {
              name: 'suggestedAnswer',
              sticky: true,
              hint: 'The suggested answer for the RFI.'
            },
            {
              name: 'location',
              sticky: true,
              type: 'object',
              properties: [
                {
                  name: 'description',
                  sticky: true,
                  hint: 'A description of the location of the RFI in the construction project.'
                }
              ]
            },
            {
              name: 'assignedTo',
              sticky: true,
              hint: 'The Autodesk ID of the assigned user.'
            },
            {
              name: 'dueDate',
              sticky: true,
              type: 'date_time',
              hint: 'The timestamp of the due date for the RFI'
            },
            {
              name: 'costImpact',
              sticky: true,
              hint: 'The cost impact status of the RFI.',
              control_type: 'select',
              pick_list: [
                ['Yes', 'Yes'],
                ['No', 'No'],
                ['Unknown', 'Unknown']
              ],
              toggle_hint: 'Select cost impact',
              toggle_field: {
                name: 'scheduleImpact',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Cost impact',
                toggle_hint: 'Enter cost impact',
                hint: 'The cost impact status of the RFI. Possible values: ' \
              '<strong>Yes, No, Unknown</strong> or leave empty.'
              }
            },
            {
              name: 'scheduleImpact',
              sticky: true,
              hint: 'The schedule impact status of the RFI.',
              control_type: 'select',
              pick_list: [
                ['Yes', 'Yes'],
                ['No', 'No'],
                ['Unknown', 'Unknown']
              ],
              toggle_hint: 'Select schedule impact',
              toggle_field: {
                name: 'scheduleImpact',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Schedule impact',
                toggle_hint: 'Enter schedule impact',
                hint: 'The schedule impact status of the RFI. Possible values: ' \
                '<strong>Yes, No, Unknown</strong> or leave empty.'
              }
            },
            {
              name: 'priority',
              sticky: true,
              control_type: 'select',
              pick_list: [
                ['High', 'High'],
                ['Normal', 'Normal'],
                ['Low', 'Low']
              ],
              hint: 'The priority status of the RFI.',
              toggle_hint: 'Select priority',
              toggle_field: {
                name: 'priority',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Priority',
                toggle_hint: 'Enter priority',
                hint: 'The priority status of the RFI. Possible values: ' \
                '<strong>High, Normal, Low</strong> or leave empty.'
              }
            },
            {
              name: 'discipline',
              sticky: true,
              hint: 'The disciplines of the RFI.',
              control_type: 'multiselect',
              delimiter: ',',
              pick_list: [
                ['Architectural', 'Architectural'],
                ['Civil/Site', 'Civil/Site'],
                ['Concrete', 'Concrete'],
                ['Electrical', 'Electrical'],
                ['Exterior Envelope', 'Exterior Envelope'],
                ['Fire Protection', 'Fire Protection'],
                ['Interior/Finishes', 'Interior/Finishes'],
                ['Landscaping', 'Landscaping'],
                ['Masonry', 'Masonry'],
                ['Mechanical', 'Mechanical'],
                ['Plumbing', 'Plumbing'],
                ['Structural', 'Structural'],
                ['Other', 'Other']
              ],
              toggle_hint: 'Select disciplines',
              toggle_field: {
                name: 'discipline',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Discipline',
                toggle_hint: 'Enter disciplines',
                hint: 'The disciplines of the RFI. Separate each discipline with a comma.'
              }
            },
            {
              name: 'category',
              sticky: true,
              hint: 'The categories of the RFI.',
              control_type: 'multiselect',
              delimiter: ',',
              pick_list: [
                ['Code Compliance', 'Code Compliance'],
                ['Constructability', 'Constructability'],
                ['Design Coordination', 'Design Coordination'],
                ['Documentation Conflict', 'Documentation Conflict'],
                ['Documentation Incomplete', 'Documentation Incomplete'],
                ['Field condition', 'Field condition'],
                ['Other', 'Other']
              ],
              toggle_hint: 'Select categories',
              toggle_field: {
                name: 'category',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Category',
                toggle_hint: 'Enter categories',
                hint: 'The categories of the RFI. Separate each category with a comma.'
              }
            },
            {
              name: 'reference',
              sticky: true,
              hint: 'An external ID; typically used when the RFI was created in another system.' \
              'Max length: 20 characters.'
            },
            {
              name: 'coReviewers',
              sticky: true,
              hint: 'Add members who can contribute to the RFI response. Separate each Autodesk ID with a comma.'
            },
            {
              name: 'distributionList',
              sticky: true,
              hint: 'Add members to receive email notifications when the RFI is updated.  ' \
              'Separate each Autodesk ID with a comma.'
            }
          ]
        end
      end
    },

    get_object_input: {
      fields: lambda do |_connection, config_fields|
        case config_fields['object']
        when 'cost'
          [
            {
              name: 'cost_object',
              label: 'Cost object',
              control_type: 'select',
              toggle_hint: 'Select cost object type',
              pick_list: 'get_cost_list',
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'cost_object',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Cost object type',
                toggle_hint: 'Enter cost object type',
              }
            }
          ].concat(
            case config_fields['cost_object']
            when 'change-order'
              [
                {
                  name: 'change_order_type',
                  label: 'Change order type',
                  control_type: 'select',
                  toggle_hint: 'Select change order type',
                  pick_list: 'change_order_list',
                  optional: false,
                  toggle_field: {
                    name: 'change_order_type',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Change order type',
                    toggle_hint: 'Enter change order type.',
                    hint: 'Possible values are: <strong>pco, rfq, rco, oco, sco</strong>.'
                  }
                }
              ]
            when 'payment'
              [
                {
                  name: 'payment_type',
                  label: 'Payment type',
                  control_type: 'select',
                  toggle_hint: 'Select payment type',
                  pick_list: [
                    ['Budget payment', 'MainContract'],
                    ['Cost payment', 'Contract']
                  ],
                  optional: false,
                  toggle_field: {
                    name: 'payment_type',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Payment type',
                    toggle_hint: 'Enter payment type',
                    hint: 'Possible values are: <strong>MainContract</strong> for budget payment and <strong>Contract</strong> for cost payment.'
                  }
                }
              ]
            else
              []
            end
          ).concat(
            [
              {
                name: 'id',
                label: 'Object ID',
                optional: false
              }
            ]
          )
        when 'folder'
          [
            {
              name: 'folder_id',
              label: 'Folder',
              control_type: 'tree',
              toggle_hint: 'Select folder',
              pick_list_params: { hub_id: 'hub_id', project_id: 'project_id' },
              tree_options: { selectable_folder: true },
              pick_list: :folders_list,
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'folder_id',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Folder ID',
                toggle_hint: 'Enter folder ID',
              }
            }
          ]
        when 'form'
          [
            {
              name: 'id',
              label: 'Form ID',
              optional: false
            }
          ]
        when 'issue'
          [
            {
              name: 'id',
              label: 'Issue ID',
              optional: false
            }
          ]
        when 'item'
          [
            {
              name: 'folder_id',
              label: 'Folder',
              control_type: 'tree',
              toggle_hint: 'Select folder',
              pick_list_params: { hub_id: 'hub_id', project_id: 'project_id' },
              tree_options: { selectable_folder: true },
              pick_list: :folders_list,
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'folder_id',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Folder ID',
                toggle_hint: 'Enter folder ID',
              }
            },
            {
              name: 'item_id',
              label: 'File name',
              control_type: 'tree',
              toggle_hint: 'Select file',
              pick_list: :folder_items,
              pick_list_params: { project_id: 'project_id', folder_id: 'folder_id' },
              optional: false,
              toggle_field: {
                name: 'item_id',
                type: 'string',
                control_type: 'text',
                change_on_blur: true,
                label: 'File ID',
                toggle_hint: 'Enter file ID',
              }
            }
          ]
        when 'rfi'
          [
            {
              name: 'id',
              label: 'RFI ID',
              optional: false
            }
          ]
        when 'takeoff'
          [
            {
              name: 'takeoff_object',
              label: 'Takeoff object',
              control_type: 'select',
              toggle_hint: 'Select takeoff object type',
              pick_list: 'get_takeoff_list',
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'takeoff_object',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Takeoff object type',
                toggle_hint: 'Enter takeoff object type',
              }
            }
          ].concat(
            case config_fields['takeoff_object']
            when 'takeoff_item'
              [
                {
                  name: 'package_id',
                  label: 'Package ID',
                  optional: false
                }
              ]
            when 'takeoff_type'
              [
                {
                  name: 'package_id',
                  label: 'Package ID',
                  optional: false
                }
              ]
            else
              []
            end
          ).concat(
            [
              {
                name: 'id',
                label: 'Object ID',
                optional: false
              }
            ]
          )
        when 'user'
          [
            {
              name: 'id',
              label: 'User ID',
              optional: false
            }
          ]
        end
      end
    },

    download_object_input: {
      fields: lambda do |_connection, config_fields|
        case config_fields['object']
        when 'item'
          [
            {
              name: 'folder_id',
              label: 'Folder',
              control_type: 'tree',
              toggle_hint: 'Select folder',
              pick_list_params: { hub_id: 'hub_id', project_id: 'project_id' },
              tree_options: { selectable_folder: true },
              pick_list: :folders_list,
              optional: false,
              toggle_field: {
                name: 'folder_id',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Folder ID',
                toggle_hint: 'Enter folder ID',
              }
            },
            {
              name: 'item_id',
              label: 'File name',
              control_type: 'tree',
              toggle_hint: 'Select file',
              pick_list: :folder_items,
              pick_list_params: { project_id: 'project_id', folder_id: 'folder_id' },
              optional: false,
              toggle_field: {
                name: 'item_id',
                type: 'string',
                control_type: 'text',
                change_on_blur: true,
                label: 'File ID',
                toggle_hint: 'Enter file ID',
              }
            }
          ]
        end
      end
    },

    search_object_input: {
      fields: lambda do |_connection, config_fields|
        case config_fields['object']
        when 'item'
          [
            {
              name: 'folder_id',
              label: 'Folder',
              control_type: 'tree',
              toggle_hint: 'Select folder',
              pick_list_params: { hub_id: 'hub_id', project_id: 'project_id' },
              tree_options: { selectable_folder: true },
              pick_list: :folders_list,
              optional: false,
              toggle_field: {
                name: 'folder_id',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Folder ID',
                toggle_hint: 'Enter folder ID'
              }
            },
            {
              name: 'file_type',
              sticky: true,
              hint: 'Return only items with the specified file type. Separate each file type with a comma, e.g: txt,jpg'
            },
            {
              name: 'file_name',
              sticky: true,
              hint: 'Return only items that contains the specified value in the file name.'
            },
            {
              name: 'updated_after',
              sticky: true,
              control_type: 'date_time',
              hint: 'Return only items updated after a specified date time.'
            },
            {
              name: 'filters',
              sticky: true,
              label: 'Additional filters',
              hint: 'Specify your own filters. A list of filters can be found ' \
              '<a href="https://forge.autodesk.com/en/docs/data/v2/developers_guide/filtering/">here</a>.'
            }
          ]
        when 'cost'
          [
            {
              name: 'cost_object',
              label: 'Cost object',
              control_type: 'select',
              toggle_hint: 'Select cost object type',
              pick_list: 'search_cost_list',
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'cost_object',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Cost object type',
                toggle_hint: 'Enter cost object type',
              }
            }
          ].concat(
            case config_fields['cost_object']
            when 'attachment'
              [
                {
                  name: 'associationId',
                  optional: false,
                  hint: 'The object ID of the item is associated to. For example the ID of the budget, ' \
                  'contract or cost item For example: <strong>18d97ae0-9484-11e8-a7ec-7ddae203e404</strong>.'
                },
                {
                  name: 'associationType',
                  optional: false,
                  control_type: 'select',
                  toggle_hint: 'Select association type',
                  pick_list: 'association_type_list',
                  hint: 'The type of the item is associated to.',
                  toggle_field: {
                    name: 'associationType',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Association type',
                    toggle_hint: 'Enter association type',
                    hint: 'The type of the item is associated to.' \
                    'Possible values: <strong>Budget, Contract, CostItem, FormInstance, Payment, BudgetPayment, Expense</strong>.'
                  }
                },
                {
                  name: 'lastModifiedSince',
                  sticky: true,
                  type: 'date_time',
                  hint: 'Retrieves items that were modified from the specified date and time, ' \
                  'in the following format, YYYY-MM-DDThh:mm:ss.sz. For example: <strong>2020-03-01T13:00:00Z</strong>.'
                }
              ]
            when 'budget'
              [
                {
                  name: 'rootId',
                  sticky: true,
                  hint: 'Query related sub-items for the given root item ID. ' \
                  'Separate multiple IDs with commas. For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'id',
                  sticky: true,
                  hint: 'The item’s primary identifier. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'code',
                  sticky: true,
                  hint: 'The item’s codes. For example: <strong>code1,code2</strong>.'
                },
                {
                  name: 'externalSystem',
                  sticky: true,
                  hint: 'The name of the external system. This name can be used to track the source ' \
                  'of truth or to search in an integrated system. For example: <strong>Sage300</strong>.'
                },
                {
                  name: 'externalId',
                  sticky: true,
                  hint: 'The ID of the item in its original external system. This ID can be used to track the source of truth ' \
                  'or to look up the data in an integrated system. Separate multiple IDs with commas. For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'lastModifiedSince',
                  sticky: true,
                  type: 'date_time',
                  hint: 'Retrieves items that were modified from the specified date and time, ' \
                  'in the following format, YYYY-MM-DDThh:mm:ss.sz. For example: <strong>2020-03-01T13:00:00Z</strong>.'
                }
              ]
            when 'change-order'
              [
                {
                  name: 'change_order_type',
                  label: 'Change order type',
                  control_type: 'select',
                  toggle_hint: 'Select change order type',
                  pick_list: 'change_order_list',
                  optional: false,
                  toggle_field: {
                    name: 'change_order_type',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Change order type',
                    toggle_hint: 'Enter change order type.',
                    hint: 'Possible values are: <strong>pco, rfq, rco, oco, sco</strong>.'
                  }
                },
                {
                  name: 'id',
                  sticky: true,
                  hint: 'The item’s primary identifier. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'contractId',
                  sticky: true,
                  hint: 'The Contract ID. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'mainContractId',
                  sticky: true,
                  hint: 'The Main Contract ID. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'budgetStatus',
                  sticky: true,
                  hint: 'The status code. Separate multiple codes with commas. ' \
                  'For example: <strong>draft,open</strong>.'
                },
                {
                  name: 'costStatus',
                  sticky: true,
                  hint: 'The status code. Separate multiple codes with commas. ' \
                  'For example: <strong>draft,open</strong>.'
                },
                {
                  name: 'externalSystem',
                  sticky: true,
                  hint: 'The name of the external system. This name can be used to track the source ' \
                  'of truth or to search in an integrated system. For example: <strong>Sage300</strong>.'
                },
                {
                  name: 'externalId',
                  sticky: true,
                  hint: 'The ID of the item in its original external system. This ID can be used to track the source of truth ' \
                  'or to look up the data in an integrated system. Separate multiple IDs with commas. For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'lastModifiedSince',
                  sticky: true,
                  type: 'date_time',
                  hint: 'Retrieves items that were modified from the specified date and time, ' \
                  'in the following format, YYYY-MM-DDThh:mm:ss.sz. For example: <strong>2020-03-01T13:00:00Z</strong>.'
                }              ]
            when 'contract'
              [
                {
                  name: 'id',
                  sticky: true,
                  hint: 'The item’s primary identifier. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'externalSystem',
                  sticky: true,
                  hint: 'The name of the external system. This name can be used to track the source ' \
                  'of truth or to search in an integrated system. For example: <strong>Sage300</strong>.'
                },
                {
                  name: 'externalId',
                  sticky: true,
                  hint: 'The ID of the item in its original external system. This ID can be used to track the source of truth ' \
                  'or to look up the data in an integrated system. Separate multiple IDs with commas. For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'lastModifiedSince',
                  sticky: true,
                  type: 'date_time',
                  hint: 'Retrieves items that were modified from the specified date and time, ' \
                  'in the following format, YYYY-MM-DDThh:mm:ss.sz. For example: <strong>2020-03-01T13:00:00Z</strong>.'
                }
              ]
            when 'cost-item'
              [
                {
                  name: 'id',
                  sticky: true,
                  hint: 'The item’s primary identifier. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'changeOrderId',
                  sticky: true,
                  hint: 'The change order ID. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'budgetId',
                  sticky: true,
                  hint: 'The ID of the budget. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'externalSystem',
                  sticky: true,
                  hint: 'The name of the external system. This name can be used to track the source ' \
                  'of truth or to search in an integrated system. For example: <strong>Sage300</strong>.'
                },
                {
                  name: 'externalId',
                  sticky: true,
                  hint: 'The ID of the item in its original external system. This ID can be used to track the source of truth ' \
                  'or to look up the data in an integrated system. Separate multiple IDs with commas. For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'lastModifiedSince',
                  sticky: true,
                  type: 'date_time',
                  hint: 'Retrieves items that were modified from the specified date and time, ' \
                  'in the following format, YYYY-MM-DDThh:mm:ss.sz. For example: <strong>2020-03-01T13:00:00Z</strong>.'
                }
              ]
            when 'document'
              [
                {
                  name: 'associationId',
                  optional: false,
                  hint: 'The object ID of the item is associated to. For example the ID of the budget, ' \
                  'contract or cost item For example: <strong>18d97ae0-9484-11e8-a7ec-7ddae203e404</strong>.'
                },
                {
                  name: 'associationType',
                  optional: false,
                  control_type: 'select',
                  toggle_hint: 'Select association type',
                  pick_list: 'association_type_list',
                  hint: 'The type of the item is associated to.',
                  toggle_field: {
                    name: 'associationType',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Association type',
                    toggle_hint: 'Enter association type',
                    hint: 'The type of the item is associated to.' \
                    'Possible values: <strong>Budget, Contract, CostItem, FormInstance, Payment, BudgetPayment, Expense</strong>.'
                  }
                },
                {
                  name: 'latest',
                  sticky: true,
                  type: 'boolean',
                  hint: 'Filter to get only the latest version of a document if it has been generated multiple times.',
                  control_type: 'select',
                  toggle_hint: 'Select value',
                  pick_list: [
                    ['Yes', 'true'],
                    ['No', 'false']
                  ],
                  toggle_field: {
                    name: 'latest',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Filter by latest',
                    toggle_hint: 'Enter value',
                    hint: 'Filter to get only the latest version of a document if it has been generated multiple times. ' \
                    'For example: <strong>true</strong>.'
                  }
                },
                {
                  name: 'signed',
                  sticky: true,
                  type: 'boolean',
                  hint: 'Filter to get only documents that have been signed.',
                  control_type: 'select',
                  toggle_hint: 'Select value',
                  pick_list: [
                    ['Yes', 'true'],
                    ['No', 'false']
                  ],
                  toggle_field: {
                    name: 'signed',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Filter by signed',
                    toggle_hint: 'Enter value',
                    hint: 'Filter to get only documents that have been signed. ' \
                    'For example: <strong>true</strong>.'
                  }
                }
              ]
            when 'expense'
              [
                {
                  name: 'id',
                  sticky: true,
                  hint: 'The item’s primary identifier. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'mainContractId',
                  sticky: true,
                  hint: 'The ID of the main contract. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'budgetPaymentId',
                  sticky: true,
                  hint: 'The ID of the budget payment used to query the related cost payment. ' \
                  'Separate multiple IDs with commas. For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'lastModifiedSince',
                  sticky: true,
                  type: 'date_time',
                  hint: 'Retrieves items that were modified from the specified date and time, ' \
                  'in the following format, YYYY-MM-DDThh:mm:ss.sz. For example: <strong>2020-03-01T13:00:00Z</strong>.'
                }
              ]
            when 'file-package'
              [
                {
                  name: 'id',
                  sticky: true,
                  hint: 'The item’s primary identifier. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'associationId',
                  sticky: true,
                  hint: 'The object ID of the item is associated to. For example the ID of the budget, ' \
                  'contract or cost item For example: <strong>18d97ae0-9484-11e8-a7ec-7ddae203e404</strong>.'
                },
                {
                  name: 'associationType',
                  sticky: true,
                  control_type: 'select',
                  toggle_hint: 'Select association type',
                  pick_list: 'association_type_list',
                  hint: 'The type of the item is associated to.',
                  toggle_field: {
                    name: 'associationType',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Association type',
                    toggle_hint: 'Enter association type',
                    hint: 'The type of the item is associated to.' \
                    'Possible values: <strong>Budget, Contract, CostItem, FormInstance, Payment, BudgetPayment, Expense</strong>.'
                  }
                }
              ]
            when 'main-contract'
              [
                {
                  name: 'id',
                  sticky: true,
                  hint: 'The item’s primary identifier. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'lastModifiedSince',
                  sticky: true,
                  type: 'date_time',
                  hint: 'Retrieves items that were modified from the specified date and time, ' \
                  'in the following format, YYYY-MM-DDThh:mm:ss.sz. For example: <strong>2020-03-01T13:00:00Z</strong>.'
                }
              ]
            when 'payment'
              [
                {
                  name: 'id',
                  sticky: true,
                  hint: 'The item’s primary identifier. Separate multiple IDs with commas. ' \
                  'For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'budgetPaymentId',
                  sticky: true,
                  hint: 'The ID of the budget payment used to query the related cost payment. ' \
                  'Separate multiple IDs with commas. For example: <strong>id1,id2</strong>.'
                },
                {
                  name: 'associationId',
                  sticky: true,
                  hint: 'The object ID of the item is associated to. For example the ID of the budget, ' \
                  'contract or cost item For example: <strong>18d97ae0-9484-11e8-a7ec-7ddae203e404</strong>.'
                },
                {
                  name: 'associationType',
                  sticky: true,
                  control_type: 'select',
                  toggle_hint: 'Select association type',
                  pick_list: [
                    ['Cost payments', 'Contract'],
                    ['Budget payments', 'MainContract']
                  ],
                  hint: 'The type of item the payment is asssociated to.',
                  toggle_field: {
                    name: 'associationType',
                    type: 'string',
                    change_on_blur: true,
                    control_type: 'text',
                    label: 'Association type',
                    toggle_hint: 'Enter association type',
                    hint: 'The type of the item is associated to.' \
                    'Possible values: <strong>Contract</strong> for cost payments and <strong>MainContract</strong> for budget payments.'
                  }
                },
                {
                  name: 'lastModifiedSince',
                  sticky: true,
                  type: 'date_time',
                  hint: 'Retrieves items that were modified from the specified date and time, ' \
                  'in the following format, YYYY-MM-DDThh:mm:ss.sz. For example: <strong>2020-03-01T13:00:00Z</strong>.'
                }
              ]
            else
              []
            end
          ).concat(
            if config_fields['cost_object'].present? && 'attachment document file-package'.exclude?(config_fields['cost_object'])
              [
                {
                  name: 'offset',
                  type: 'number',
                  sticky: true,
                  hint: 'The number of items to skip before starting to collect the result set.'
                },
                {
                  name: 'limit',
                  type: 'number',
                  sticky: true,
                  hint: 'The maximum number of items to return.'
                },
                {
                  name: 'sort',
                  sticky: true,
                  hint: 'The sort order for items. Each attribute can be sorted in either <strong>asc</strong> (default) or <strong>desc</strong> order.' \
                  'For example: <strong>name, updatedAt desc</strong> sorts the results first by name in ascending order, then by date updated in descending order.'
                }
              ]
            else
              []
            end
          )
        when 'form'
          [
            {
              name: 'templateId',
              label: 'Form template',
              sticky: true,
              control_type: 'select',
              pick_list: 'form_templates',
              pick_list_params: { project_id: 'project_id' },
              extends_schema: true,
              toggle_hint: 'Select form template',
              hint: 'Only 50 form templates are available for selection. If your template is not shown above, please use a template ID.',
              toggle_field: {
                name: 'templateId',
                label: 'Form template',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                toggle_hint: 'Enter form template ID',
                hint: 'Return Forms on template with given ID.',
              }
            },
            {
              name: 'statuses',
              type: 'string',
              control_type: :select,
              sticky: true,
              pick_list: [
                [ 'Draft', 'draft' ],
                [ 'Submitted', 'submitted' ],
                [ 'Archived', 'archived' ]
              ],
              toggle_hint: 'Select form status',
              toggle_field: {
                name: 'statuses',
                type: 'string',
                label: 'Form status',
                toggle_hint: 'Enter form status',
                hint: 'Filter based on form status. Possible options: <b>draft</b>, <b>submitted</b>, <b>archived</b>.',
              }
            },
            {
              name: 'ids',
              label: 'Form IDs',
              type: 'string',
              sticky: true,
              hint: 'An comma separated list of Form IDs to retrieve.'
            },
            {
              name: 'formDateMin',
              type: 'date',
              sticky: true,
              hint: 'Return Forms with formDate at or after specified date.'
            },
            {
              name: 'formDateMax',
              type: 'date',
              sticky: true,
              hint: 'Return Forms with formDate at or before specified date.'
            },
            {
              name: 'updatedAfter',
              type: 'date_time',
              sticky: true,
              hint: 'Return Forms updated after a specified time.',
              convert_input: 'render_iso8601_timestamp'
            },
            {
              name: 'updatedBefore',
              type: 'date_time',
              sticky: true,
              hint: 'Return Forms updated before a specified time.',
              convert_input: 'render_iso8601_timestamp'
            },
            {
              name: 'sortBy',
              type: 'string',
              sticky: true,
              hint: 'Return Forms sorted by specified attribute.'
            },
            {
              name: 'sortOrder',
              type: 'string',
              sticky: true,
              hint: 'Return Forms in specified sorted order. Possible values are: <b>asc</b>, <b>desc</b>.'
            },
            {
              name: 'offset',
              type: 'integer',
              sticky: true,
              hint: 'The number of records to skip before returning the result records. Defaults to 0. Increase this value in subsequent requests to continue getting results when the number of records exceeds the requested limit.'
            },
            {
              name: 'limit',
              type: 'integer',
              sticky: true,
              hint: 'The number of records to return in a single request. Can be a number between 1 and 50. Defaults to 50.'
            }
          ]
        when 'issue'
          [
            {
              name: 'issueTypeId',
              label: 'Issue type',
              control_type: 'select',
              toggle_hint: 'Select issue type',
              pick_list: 'search_issue_type',
              pick_list_params: { project_id: 'project_id' },
              optional: true,
              sticky: true,
              extends_schema: true,
              toggle_field: {
                name: 'issueTypeId',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Issue type ID',
                toggle_hint: 'Enter issue type ID',
                hint: 'Filter issues by the unique identifier of the type of the issue. Separate multiple values with commas.'
              }
            },
            {
              name: 'issueSubtypeId',
              label: 'Issue sub type',
              control_type: 'select',
              toggle_hint: 'Select issue sub type',
              pick_list: 'search_issue_sub_type',
              pick_list_params: { project_id: 'project_id', issue_type_id: 'issueTypeId' },
              sticky: true,
              toggle_field: {
                name: 'issueSubtypeId',
                type: 'string',
                control_type: 'text',
                change_on_blur: true,
                label: 'Issue sub type ID',
                toggle_hint: 'Enter issue subtype ID',
                hint: 'Filter issues by the unique identifier of the subtype of the issue. Separate multiple values with commas.'
              }
            },
            {
              name: 'status',
              sticky: true,
              control_type: 'multiselect',
              delimiter: ',',
              toggle_hint: 'Select issue status',
              pick_list: [
                ['Open', 'open'],
                ['Pending', 'pending'],
                ['In review', 'in_review'],
                ['Closed', 'closed']
              ],
              sticky: true,
              toggle_field: {
                name: 'status',
                type: 'string',
                control_type: 'text',
                label: 'Issue status',
                change_on_blur: true,
                toggle_hint: 'Enter issue status',
                hint: 'Filter issues by the unique identifier of the current status of the issue. Separate multiple values with commas. Possible options include: `open`, `pending`, `in_review`, `closed`'
              }
            },
            {
              name: 'published',
              sticky: true,
              control_type: 'select',
              toggle_hint: 'Select published status',
              pick_list: [
                ['Yes', 'true'],
                ['No', 'false']
              ],
              sticky: true,
              toggle_field: {
                name: 'published',
                type: 'string',
                control_type: 'text',
                label: 'Published status',
                change_on_blur: true,
                toggle_hint: 'Enter published status',
                hint: 'Filter issues by published status (true/false)'
              }
            },
            {
              name: 'deleted',
              sticky: true,
              control_type: 'select',
              toggle_hint: 'Select deleted status',
              pick_list: [
                ['Yes', 'true'],
                ['No', 'false']
              ],
              sticky: true,
              toggle_field: {
                name: 'deleted',
                type: 'string',
                control_type: 'text',
                label: 'Deleted status',
                change_on_blur: true,
                toggle_hint: 'Enter deleted status',
                hint: 'Show deleted issues (only admin). Default is false.'
              }
            },
            {
              name: 'assignedToType',
              sticky: true,
              control_type: 'select',
              toggle_hint: 'Select assignee type',
              extends_schema: true,
              pick_list: [
                ['Company', 'company'],
                ['Role', 'role'],
                ['User', 'user']
              ],
              sticky: true,
              toggle_field: {
                name: 'assignedToType',
                type: 'string',
                label: 'Assignee type',
                control_type: 'text',
                change_on_blur: true,
                toggle_hint: 'Enter assignee type',
                hint: 'Filter issues by the type of the current assignee of this issue. Separate multiple values with commas. Possible values: user, company, role'
              }
            },
            {
              name: 'assignedTo',
              sticky: true,
              hint: 'Filter issues by the unique identifier of the current assignee of this issue. Separate multiple values with commas'
            },
            {
              name: 'createdBy',
              sticky: true,
              hint: 'Filter issues by the unique identifier of the user who created the issue. Separate multiple values with commas'
            },
            {
              name: 'updatedBy',
              sticky: true,
              hint: 'Filter issues by the unique identifier of the user who updated the issue. Separate multiple values with commas'
            },
            {
              name: 'closedBy',
              sticky: true,
              hint: 'Filter issues by the unique LBS (Location Breakdown Structure) identifier that relates to the issue and retreives also all issues with sub locations. Separate multiple values with commas'
            },
            {
              name: 'dueDate',
              sticky: true,
              hint: 'Filter issues by due date. For example, use 2018-05-09...2018-05-10 (Date range), or 2018-05-09... (Greater-than or equal to), or ...2018-05-09 (Less-than or equal to)'
            },
            {
              name: 'startDate',
              sticky: true,
              hint: 'Filter issues by start date. For example, use 2018-05-09...2018-05-10 (Date range), or 2018-05-09... (Greater-than or equal to), or ...2018-05-09 (Less-than or equal to)'
            },
            {
              name: 'createdAt',
              sticky: true,
              hint: 'Filter issues created at(or since) specified date and time. For example, use 2018-05-09...2018-05-10 (Date range), or 2018-05-09... (Greater-than or equal to), or ...2018-05-09 (Less-than or equal to)'
            },
            {
                name: 'openedAt',
                sticky: true,
                hint: 'Filter issues opened at specified date and time. For example, use 2018-05-09...2018-05-10 (Date range), or 2018-05-09... (Greater-than or equal to), or ...2018-05-09 (Less-than or equal to)'
            },
            {
                name: 'updatedAt',
                sticky: true,
                hint: 'Filter issues updated within a specified date range. For example, use filter[updatedAt]=2018-05-11T00:00:00%2B02:00...2018-05-12T00:00:00%2B02:00'
            },
            {
              name: 'closedAt',
              sticky: true,
              hint: 'Filter issues closed within a specified date range. For example, use 2018-05-09...2018-05-10 (Date range), or 2018-05-09... (Greater-than or equal to), or ...2018-05-09 (Less-than or equal to)'
            },
            {
              name: 'id',
              sticky: true,
              hint: 'Filter issues by the unique issue ID. Separate multiple values with commas'
            },
            {
              name: 'rootCauseId',
              sticky: true,
              hint: 'Filter issues by the unique identifier of the type of root cause for the issue. Separate multiple values with commas'
            },
            {
              name: 'locationId',
              sticky: true,
              hint: 'Filter issues by the unique LBS (Location Breakdown Structure) identifier that relates to the issue. Separate multiple values with commas'
            },
            {
              name: 'subLocationId',
              sticky: true,
              hint: 'Filter issues by the unique LBS (Location Breakdown Structure) identifier that relates to the issue and retreives also all issues with sub locations. Separate multiple values with commas'
            },
            {
              name: 'displayId',
              sticky: true,
              hint: 'Filter issues by the chronological user-friendly identifier. Separate multiple values with commas'
            },
            {
              name: 'title',
              sticky: true,
              hint: 'Filter issues by title. For example, use filter[title]=my title'
            },
            {
              name: 'customAttributes',
              sticky: true,
              hint: 'Filter issues by the custom attributes. Each custom attribute filter should be defined by its uuid. For example, filter[customAttributes][f227d940-ae9b-4722-9297-389f4411f010]=1,2,3. Separate multiple values with commas'
            },
            {
              name: 'fields',
              sticky: true,
              hint: 'Return only specific fields in issue object. Separate multiple values with commas. Fields which will be returned in any case: id, title, status, issueTypeId'
            },
            {
              name: 'sort',
              sticky: true,
              hint: 'Sort issues by specified fields. Separate multiple values with commas. To sort in descending order add a - before the sort criteria. For example, sortBy=status,-displayId,-dueDate,customAttributes[5c07cbe2-256a-48f1-b35b-2e5e00914104]'
            },
            {
              name: 'limit',
              sticky: true,
              type: 'integer',
              hint: 'Return specified number of issues. Acceptable values are 1-100. Default value is 100'
            },
            {
              name: 'offset',
              sticky: true,
              type: 'integer',
              hint: 'Return issues starting from the specified offset number. Default value is 0'
            },
          ]
        when 'rfi'
          [
            {
              name: 'limit',
              sticky: true,
              type: 'integer',
              hint: 'The number of RFIs to return in the response payload. ' \
              'Acceptable values: 1-200. Default value: 10.'
            },
            {
              name: 'offset',
              sticky: true,
              type: 'integer',
              hint: 'The number of RFIs to skip in the set of results.'
            },
            {
              name: 'sort',
              sticky: true,
              hint: 'Sort the RFIs by <strong>createdAt, status, dueDate, title, location, ' \
              'updatedAt, costImpact, scheduleImpact, priority, discipline, category, ' \
              'reference, customIdentifier</strong>. For example, <strong>status ASC</strong> to sort ' \
              'by the <strong>status</strong> field in ascending order. ' \
              'Separate multiple values with commas. To sort in descending order add a <strong>DESC</strong> ' \
              'after the sort criteria. For example, <strong>status DESC</strong>.'
            },
            {
              name: 'status',
              sticky: true,
              hint: 'Retrieves RFIs with the specified status. Possible values: ' \
              '<strong>draft, submitted, open, rejected, answered, closed, void</strong>.'
            },
            {
              name: 'createdAt',
              sticky: true,
              type: 'date_time',
              hint: 'Retrieves RFIs created after the specfied date, in the following format: ' \
              'YYYY-MM-DDThh:mm:ss.sz.'
            },
            {
              name: 'dueDate',
              sticky: true,
              type: 'date_time',
              hint: 'Retrieves RFIs with the specified due date, in the following format: ' \
              'YYYY-MM-DDThh:mm:ss.sz.'
            },
            {
              name: 'search',
              sticky: true,
              hint: 'Searches for a specified string in the following fields: ' \
              '<strong>title, question, officialResponse</strong>, and retrieves ' \
              'RFIs where the string is found. This includes RFIs where the string ' \
              'matches part of a field.'
            },
            {
              name: 'costImpact',
              sticky: true,
              hint: 'Retrieves RFIs with the specified cost impact value. ' \
              'For example: <strong>Yes</strong>.'
            },
            {
              name: 'scheduleImpact',
              sticky: true,
              hint: 'Retrieves RFIs with the specified schedule impact value. ' \
              'For example: <strong>Yes</strong>.'
            },
            {
              name: 'priority',
              sticky: true,
              hint: 'Retrieves RFIs with the specified priority level. ' \
              'For example: <strong>High</strong>.'
            },
            {
              name: 'discipline',
              sticky: true,
              hint: 'Retrieves RFIs with the specified discipline type. ' \
              'For example: <strong>Architectural</strong>.'
            },
            {
              name: 'category',
              sticky: true,
              hint: 'Retrieves RFIs with the specified category type. ' \
              'For example: <strong>Constructability</strong>.'
            }
          ]
        when 'rfi_reference'
          [
            {
              name: 'id',
              label: 'RFI ID',
              optional: false
            },
            {
              name: 'includeDeleted',
              sticky: true,
              control_type: 'select',
              pick_list: [
                ['Yes', 'true'],
                ['No', 'false']
              ],
              hint: 'Whether or not to include deleted relationships in the search.'
            },
            {
              name: 'pageLimit',
              sticky: true,
              type: 'integer',
              hint: 'The maximum number of relationships to return in a page. ' \
              'If not set, the default page limit is used, as determined by the server.'
            },
            {
              name: 'continuationToken',
              sticky: true,
              hint: 'The token indicating the start of the page. ' \
              'If not set, the first page is retrieved.'
            }
          ]
        when 'rfi_comment'
          [
            {
              name: 'id',
              label: 'RFI ID',
              optional: false,
            },
            {
              name: 'limit',
              sticky: true,
              type: 'integer',
              hint: 'The number of RFIs to return in the response payload. Acceptable values: ' \
              '<strong>1-200</strong>. Default value: 10.'
            },
            {
              name: 'offset',
              sticky: true,
              type: 'integer',
              hint: 'The number of comments to skip in the set of results.'
            }
          ]
        when 'takeoff'
          [
            {
              name: 'takeoff_object',
              label: 'Takeoff object',
              control_type: 'select',
              toggle_hint: 'Select takeoff object type',
              pick_list: 'search_takeoff_list',
              optional: false,
              extends_schema: true,
              toggle_field: {
                name: 'takeoff_object',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Takeoff object type',
                toggle_hint: 'Enter takeoff object type',
              }
            }
          ].concat(
            case config_fields['takeoff_object']
            when 'takeoff_item'
              [
                {
                  name: 'package_id',
                  optional: false
                }
              ]
            when 'takeoff_type'
              [
                {
                  name: 'package_id',
                  optional: false
                }
              ]
            when 'classification'
              [
                {
                  name: 'classification_id',
                  optional: false
                }
              ]
            else
              []
            end
          ).concat(
            [
              {
                name: 'offset',
                type: 'number',
                sticky: true,
                hint: 'The number of items to skip before starting to collect the result set.'
              },
              {
                name: 'limit',
                type: 'number',
                sticky: true,
                hint: 'The maximum number of items to return.'
              }
            ]
          )
        end
      end
    },

    upload_object_input: {
      fields: lambda do |_connection, config_fields|
        case config_fields['object']
        when 'item'
          [
            {
              name: 'folder_id',
              label: 'Folder',
              control_type: 'tree',
              hint: 'Select folder',
              toggle_hint: 'Select folder',
              pick_list_params: { hub_id: 'hub_id', project_id: 'project_id' },
              tree_options: { selectable_folder: true },
              pick_list: :folders_list,
              optional: false,
              toggle_field: {
                name: 'folder_id',
                type: 'string',
                change_on_blur: true,
                control_type: 'text',
                label: 'Folder ID',
                toggle_hint: 'Enter folder ID',
                hint: 'Get ID from url of the folder page.'
              }
            },
            {
              name: 'item_id',
              label: 'File name',
              control_type: 'tree',
              hint: 'If versioning an existing file, select the file to update.',
              toggle_hint: 'Select file',
              pick_list: :folder_items,
              pick_list_params: { project_id: 'project_id', folder_id: 'folder_id' },
              optional: true,
              sticky: true,
              toggle_field: {
                name: 'item_id',
                type: 'string',
                control_type: 'text',
                change_on_blur: true,
                label: 'File ID',
                toggle_hint: 'Enter file ID',
                hint: 'If versioning an existing file, provide file ID.'
              }
            },
            {
              name: 'name',
              optional: false,
              hint: 'The name of the file (1-255 characters). Reserved characters: <, >, :, ", /, \, |, ?, *, `, \n, \r, \t, \0, \f, ¢, ™, $, ®.'
            },
            {
              name: 'file_content',
              optional: false
            }
          ]
        end
      end
    },

    object_output_response: {
      fields: lambda do |_connection, config_fields|
        case config_fields['object']
        when 'project'
          [
            { name: 'attributes', type: 'object', properties: [
              { name: 'name' },
              { name: 'scopes', properties: 'array', of: 'string' },
              { name: 'extension', type: 'object', properties: [
                { name: 'type' },
                { name: 'version' },
                { name: 'schema', type: 'object', properties: [
                  { name: 'href' }
                ]},
                { name: 'data', type: 'object', properties: [
                  { name: 'projectType' }
                ]}
              ]}
            ]},
            { name: 'links', type: 'object', properties: [
              { name: 'self', type: 'object', properties: [
                { name: 'href' }
              ]}
            ]},
            { name: 'relationships', type: 'object', properties: [
              { name: 'hub', type: 'object', properties: [
                { name: 'data', type: 'object', properties: [
                  { name: 'type' },
                  { name: 'id' }
                ]},
                { name: 'links', type: 'object', properties: [
                  { name: 'related', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]},
              { name: 'rootFolder', type: 'object', properties: [
                { name: 'data', type: 'object', properties: [
                  { name: 'type' },
                  { name: 'id' }
                ]},
                { name: 'meta', type: 'object', properties: [
                  { name: 'link', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]},
              { name: 'topFolders', type: 'object', properties: [
                { name: 'links', type: 'object', properties: [
                  { name: 'related', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]}
            ]}
          ]
        when 'folder'
          [
            { name: 'id', label: 'Folder ID' },
            { name: 'attributes', type: 'object', properties: [
              { name: 'name' },
              { name: 'displayName' },
              { name: 'createTime', type: 'date_time' },
              { name: 'createUserId' },
              { name: 'createUserName' },
              { name: 'lastModifiedTime', type: 'date_time' },
              { name: 'lastModifiedUserId' },
              { name: 'lastModifiedUserName' },
              { name: 'lastModifiedTimeRollup', type: 'date_time' },
              { name: 'objectCount', type: 'number' },
              { name: 'hidden', type: 'boolean' },
              { name: 'extension', type: 'object', properties: [
                { name: 'type' },
                { name: 'version' },
                { name: 'schema', type: 'object', properties: [
                  { name: 'href' }
                ]}
              ]},
              { name: 'data', type: 'object', properties: [
                { name: 'visibleTypes', type: 'array', of: 'string' },
                { name: 'actions', type: 'array', of: 'string' },
                { name: 'allowedTypes', type: 'array', of: 'string' }
              ]}
            ]},
            { name: 'links', type: 'object', properties: [
              { name: 'self', type: 'object', properties: [
                { name: 'href' }
              ]}
            ]},
            { name: 'relationships', type: 'object', properties: [
              { name: 'contents', type: 'object', properties: [
                { name: 'links', type: 'object', properties: [
                  { name: 'related', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]},
              { name: 'parent', type: 'object', properties: [
                { name: 'data', type: 'object', properties: [
                  { name: 'type' },
                  { name: 'id' }
                ]},
                { name: 'links', type: 'object', properties: [
                  { name: 'related', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]},
              { name: 'refs', type: 'object', properties: [
                { name: 'links', type: 'object', properties: [
                  { name: 'self', type: 'object', properties: [
                    { name: 'href' }
                  ]},
                  { name: 'related', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]},
              { name: 'links', type: 'object', properties: [
                { name: 'links', type: 'object', properties: [
                  { name: 'self', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]}
            ]}
          ]
        when 'item'
          [
            { name: 'id', label: 'Document ID' },
            { name: 'attributes', type: 'object', properties: [
              { name: 'displayName' },
              { name: 'createTime', type: 'date_time' },
              { name: 'createUserId' },
              { name: 'createUserName' },
              { name: 'lastModifiedTime', type: 'date_time' },
              { name: 'lastModifiedUserId' },
              { name: 'lastModifiedUserName' },
              { name: 'pathInProject' },
              { name: 'hidden', type: 'boolean' },
              { name: 'reserved', type: 'boolean' },
              { name: 'extension', type: 'object', properties: [
                { name: 'type' },
                { name: 'version' },
                { name: 'schema', type: 'object', properties: [
                  { name: 'href' }
                ]},
                { name: 'data', type: 'object', properties: [
                  { name: 'sourceFileName' }
                ]}
              ]}
            ]},
            { name: 'links', type: 'object', properties: [
              { name: 'self', type: 'object', properties: [
                { name: 'href' }
              ]}
            ]},
            { name: 'relationships', type: 'object', properties: [
              { name: 'tip', type: 'object', properties: [
                { name: 'data', type: 'object', properties: [
                  { name: 'type' },
                  { name: 'id' }
                ]},
                { name: 'links', type: 'object', properties: [
                  { name: 'related', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]},
              { name: 'versions', type: 'object', properties: [
                { name: 'links', type: 'object', properties: [
                  { name: 'related', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]},
              { name: 'parent', type: 'object', properties: [
                { name: 'data', type: 'object', properties: [
                  { name: 'type' },
                  { name: 'id' }
                ]},
                { name: 'links', type: 'object', properties: [
                  { name: 'related', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]},
              { name: 'refs', type: 'object', properties: [
                { name: 'links', type: 'object', properties: [
                  { name: 'self', type: 'object', properties: [
                    { name: 'href' }
                  ]},
                  { name: 'related', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]},
              { name: 'links', type: 'object', properties: [
                { name: 'links', type: 'object', properties: [
                  { name: 'self', type: 'object', properties: [
                    { name: 'href' }
                  ]}
                ]}
              ]}
            ]}
          ]
        when 'cost'
          case config_fields['cost_object']
          when 'attachment'
            [
              { name: 'id', label: 'Attachment ID' },
              { name: 'folderId' },
              { name: 'urn' },
              { name: 'type' },
              { name: 'name' },
              { name: 'associationId' },
              { name: 'associationType' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'updatedAt', type: 'date_time' }
            ]
          when 'budget'
            [
              { name: 'id', label: 'Budget ID' },
              { name: 'parentId' },
              { name: 'code' },
              { name: 'name' },
              { name: 'description' },
              { name: 'quantity', type: 'number' },
              { name: 'unitPrice', type: 'number' },
              { name: 'unit' },
              { name: 'originalAmount', type: 'number' },
              { name: 'internalAdjustment', type: 'number' },
              { name: 'approvedOwnerChanges', type: 'number' },
              { name: 'pendingOwnerChanges', type: 'number' },
              { name: 'originalCommitment', type: 'number' },
              { name: 'approvedChangeOrders', type: 'number' },
              { name: 'approvedInScopeChangeOrders', type: 'number' },
              { name: 'pendingChangeOrders', type: 'number' },
              { name: 'reserves', type: 'number' },
              { name: 'actualQuantity', type: 'number' },
              { name: 'actualUnitPrice', type: 'number' },
              { name: 'actualCost', type: 'number' },
              { name: 'contractId' },
              { name: 'mainContractId' },
              { name: 'adjustments', type: 'object', properties: [
                { name: 'total', type: 'number' },
                { name: 'details', type: 'array', of: 'object', properties: [
                  { name: 'quantity', type: 'number' },
                  { name: 'unitPrice', type: 'number' },
                  { name: 'unit' }
                ]},
                { name: 'updatedAt', type: 'date_time' }
              ]},
              { name: 'uncommitted', type: 'number' },
              { name: 'revised', type: 'number' },
              { name: 'projectedCost', type: 'number' },
              { name: 'projectedBudget', type: 'number' },
              { name: 'forecastFinalCost', type: 'number' },
              { name: 'forecastVariance', type: 'number' },
              { name: 'forecastCostComplete', type: 'number' },
              { name: 'varianceTotal', type: 'number' },
              { name: 'externalId' },
              { name: 'externalSystem' },
              { name: 'externalMessage' },
              { name: 'lastSyncTime', type: 'date_time' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'updatedAt', type: 'date_time' }
            ]
          when 'change-order'
            [
              { name: 'id', label: 'Change order ID' },
              { name: 'number' },
              { name: 'name' },
              { name: 'description' },
              { name: 'type' },
              { name: 'scope' },
              { name: 'creatorId' },
              { name: 'ownerId' },
              { name: 'changedBy' },
              { name: 'markupFormulaId' },
              { name: 'appliedBy' },
              { name: 'appliedAt' },
              { name: 'budgetStatus' },
              { name: 'costStatus' },
              { name: 'estimated' },
              { name: 'proposed' },
              { name: 'submitted' },
              { name: 'approved' },
              { name: 'committed' },
              { name: 'scopeOfWork' },
              { name: 'note' },
              { name: 'externalId' },
              { name: 'externalSystem' },
              { name: 'externalMessage' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'updatedAt', type: 'date_time'},
              { name: 'properties', type: 'array', of: 'object', properties: [
                { name: 'name' },
                { name: 'builtIn', type: 'boolean' },
                { name: 'position', type: 'number' },
                { name: 'propertyDefinitionId' },
                { name: 'type' },
                { name: 'value' }
              ]},
              { name: 'costItems', type: 'array', of: 'object', properties: [
                { name: 'id' }
              ]}
            ]
          when 'contract'
            [
              { name: 'id', label: 'Contract ID' },
              { name: 'code' },
              { name: 'name' },
              { name: 'description' },
              { name: 'companyId' },
              { name: 'type' },
              { name: 'contactId' },
              { name: 'signedBy' },
              { name: 'ownerId' },
              { name: 'status' },
              { name: 'changedBy' },
              { name: 'creatorId' },
              { name: 'awarded', type: 'number' },
              { name: 'changes', type: 'number' },
              { name: 'total', type: 'number' },
              { name: 'originalBudget', type: 'number' },
              { name: 'internalAdjustment', type: 'number' },
              { name: 'approvedOwnerChanges', type: 'number' },
              { name: 'pendingOwnerChanges', type: 'number' },
              { name: 'approvedChangeOrders', type: 'number' },
              { name: 'approvedInScopeChangeOrders', type: 'number' },
              { name: 'pendingChangeOrders', type: 'number' },
              { name: 'reserves', type: 'number' },
              { name: 'actualCost', type: 'number' },
              { name: 'uncommitted', type: 'number' },
              { name: 'revised', type: 'number' },
              { name: 'projectedCost', type: 'number' },
              { name: 'projectedBudget', type: 'number' },
              { name: 'forecastFinalCost', type: 'number' },
              { name: 'forecastVariance', type: 'number' },
              { name: 'forecastCostComplete', type: 'number' },
              { name: 'varianceTotal', type: 'number' },
              { name: 'awardedAt', type: 'date_time' },
              { name: 'statusChangedAt', type: 'date_time' },
              { name: 'documentGeneratedAt', type: 'date_time' },
              { name: 'sentAt', type: 'date_time' },
              { name: 'respondedAt', type: 'date_time' },
              { name: 'returnedAt', type: 'date_time' },
              { name: 'onsiteAt', type: 'date_time' },
              { name: 'offsiteAt', type: 'date_time' },
              { name: 'procuredAt', type: 'date_time' },
              { name: 'approvedAt', type: 'date_time' },
              { name: 'scopeOfWork' },
              { name: 'note' },
              { name: 'paymentDue', type: 'integer' },
              { name: 'budgets', type: 'array', of: 'object', properties: [
                { name: 'id' },
                { name: 'mainContractId' }
              ]},
              { name: 'adjustments', type: 'object', properties: [
                { name: 'total', type: 'number' },
                { name: 'details', type: 'array', of: 'object', properties: [
                  { name: 'quantity', type: 'number' },
                  { name: 'unitPrice', type: 'number' },
                  { name: 'unit' }
                ]},
                { name: 'updatedAt', type: 'date_time' }
              ]},
              { name: 'properties', type: 'array', of: 'object', properties: [
                { name: 'name' },
                { name: 'value' },
                { name: 'propertyDefinitionId' },
                { name: 'position', type: 'integer' },
                { name: 'builtIn', type: 'boolean' },
                { name: 'type' }
              ]},
              { name: 'externalId' },
              { name: 'externalSystem' },
              { name: 'externalMessage' },
              { name: 'lastSyncTime', type: 'date_time' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'updatedAt', type: 'date_time' }
            ]
          when 'cost-item'
            [
              { name: 'id', label: 'Cost item ID' },
              { name: 'number' },
              { name: 'name' },
              { name: 'description' },
              { name: 'budgetStatus' },
              { name: 'costStatus' },
              { name: 'scope' },
              { name: 'type' },
              { name: 'isMarkup', type: 'boolean' },
              { name: 'estimated', type: 'number' },
              { name: 'proposed', type: 'number' },
              { name: 'submitted', type: 'number' },
              { name: 'approved', type: 'number' },
              { name: 'committed', type: 'number' },
              { name: 'quantity', type: 'number' },
              { name: 'unit' },
              { name: 'scopeOfWork' },
              { name: 'note' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'updatedAt', type: 'date_time' }
            ]
          when 'document'
            [
              { name: 'id', label: 'Document ID' },
              { name: 'templateId' },
              { name: 'recipientId' },
              { name: 'signedBy' },
              { name: 'urn' },
              { name: 'pdfUrn' },
              { name: 'signedUrn' },
              { name: 'status' },
              { name: 'jobId', type: 'number' },
              { name: 'errorInfo', type: 'object', properties: [
                { name: 'code' },
                { name: 'message' },
                { name: 'detail' }
              ]},
              { name: 'associationId' },
              { name: 'associationType' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'updatedAt', type: 'date_time'  }
            ]
          when 'expense'
            [
              { name: 'id', label: 'Expense ID' },
              { name: 'supplierId' },
              { name: 'supplierName' },
              { name: 'mainContractId' },
              { name: 'budgetPaymentId' },
              { name: 'number' },
              { name: 'name' },
              { name: 'description' },
              { name: 'note' },
              { name: 'term' },
              { name: 'referenceNumber' },
              { name: 'type' },
              { name: 'scope' },
              { name: 'creatorId' },
              { name: 'changedBy' },
              { name: 'purchasedBy' },
              { name: 'status' },
              { name: 'amount', type: 'number' },
              { name: 'externalId' },
              { name: 'externalSystem' },
              { name: 'externalMessage' },
              { name: 'lastSyncTime', type: 'date_time' },
              { name: 'paymentDue' },
              { name: 'issuedAt', type: 'date_time' },
              { name: 'receivedAt', type: 'date_time' },
              { name: 'approvedAt', type: 'date_time' },
              { name: 'paidAt', type: 'date_time' },
              { name: 'paidAmount', type: 'number' },
              { name: 'paymentType' },
              { name: 'paymentReference' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'updatedAt', type: 'date_time' },
              { name: 'expenseItems', type: 'array', of: 'object', properties: [
                { name: 'id' },
                { name: 'containerId' },
                { name: 'expenseId' },
                { name: 'contractId' },
                { name: 'budgetId' },
                { name: 'number' },
                { name: 'name' },
                { name: 'description' },
                { name: 'note' },
                { name: 'quantity', type: 'integer' },
                { name: 'unitPrice', type: 'number' },
                { name: 'unit' },
                { name: 'amount', type: 'number' },
                { name: 'tax', type: 'number' },
                { name: 'scope' },
                { name: 'createdAt', type: 'date_time' },
                { name: 'updatedAt', type: 'date_time' },
                { name: 'aggregateBy' },
                { name: 'properties' },
                { name: 'budget' },
                { name: 'contract' },
                { name: 'externalId' },
                { name: 'externalSystem' },
                { name: 'externalMessage' },
                { name: 'lastSyncTime', type: 'date_time' }
              ]},
              { name: 'properties', type: 'array', of: 'object', properties: [
                { name: 'name' },
                { name: 'value' },
                { name: 'propertyDefinitionId' },
                { name: 'position', type: 'integer' },
                { name: 'builtIn', type: 'boolean' },
                { name: 'type' }
              ]},
              { name: 'mainContract', type: 'object', properties: [
                { name: 'id' },
                { name: 'code' },
                { name: 'name'}
              ]}
            ]
          when 'file-package'
            [
              { name: 'id', label: 'File package ID' },
              { name: 'recipient' },
              { name: 'urn' },
              { name: 'errorInfo', type: 'object', properties: [
                { name: 'code' },
                { name: 'message' },
                { name: 'detail' }
              ]},
              { name: 'items', type: 'object', properties: [
                { name: 'id', label: 'Item ID' },
                { name: 'urn' },
                { name: 'name' },
                { name: 'type' },
                { name: 'createdAt', type: 'date_time' },
                { name: 'updatedAt', type: 'date_time' }
              ]},
              { name: 'createdAt', type: 'date_time' },
              { name: 'updatedAt', type: 'date_time' }
            ]
          when 'main-contract'
            [
              { name: 'id', label: 'Main contract ID' },
              { name: 'code' },
              { name: 'name' },
              { name: 'note' },
              { name: 'scopeOfWork' },
              { name: 'description' },
              { name: 'type' },
              { name: 'contactId' },
              { name: 'creatorId' },
              { name: 'signedBy' },
              { name: 'changedBy' },
              { name: 'ownerCompanyId' },
              { name: 'contractorCompanyId' },
              { name: 'status' },
              { name: 'amount', type: 'number' },
              { name: 'approvedChangeOrder', type: 'number' },
              { name: 'revised', type: 'number' },
              { name: 'paid', type: 'number' },
              { name: 'billToDate', type: 'number' },
              { name: 'remaining', type: 'number' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'updatedAt', type: 'date_time' },
              { name: 'start_date', type: 'date' },
              { name: 'executedDate', type: 'date' },
              { name: 'start_date', type: 'date' },
              { name: 'plannedCompletionDate', type: 'date' },
              { name: 'actualCompletionDate', type: 'date' },
              { name: 'closeDate', type: 'date' },
              { name: 'isDefault', type: 'boolean' },
              { name: 'paymentDue', type: 'integer' },
              { name: 'unReceived', type: 'integer' },
              { name: 'externalId' },
              { name: 'externalSystem' },
              { name: 'externalMessage' },
              { name: 'lastSyncTime', type: 'integer' }
            ]
          when 'payment'
            [
              { name: 'id', label: 'Payment ID' },
              { name: 'number' },
              { name: 'name' },
              { name: 'associationId' },
              { name: 'associationType' },
              { name: 'mainContractId' },
              { name: 'budgetPaymentId' },
              { name: 'billingPeriod' },
              { name: 'startDate', type: 'date' },
              { name: 'endDate', type: 'date' },
              { name: 'description' },
              { name: 'note' },
              { name: 'status' },
              { name: 'hasComment', type: 'boolean' },
              { name: 'paidAt', type: 'date_time' },
              { name: 'paidAmount', type: 'number' },
              { name: 'paymentType' },
              { name: 'paymentReference' },
              { name: 'originalAmount', type: 'number' },
              { name: 'contractAmount', type: 'number' },
              { name: 'amount', type: 'number' },
              { name: 'previousAmount', type: 'number' },
              { name: 'completeWorkRetention', type: 'number' },
              { name: 'materialsOnStoreRetention', type: 'number' },
              { name: 'previousRetention', type: 'number' },
              { name: 'materailsOnStore', type: 'number' },
              { name: 'previousMaterialsOnStore', type: 'number' },
              { name: 'approvedChangeOrders', type: 'number' },
              { name: 'previousApprovedChangeOrders', type: 'number' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'updatedAt', type: 'date_time' }
            ]
          when 'performance-tracking-item-instance'
            [
              { name: 'id' },
              { name: 'number' },
              { name: 'name' },
              { name: 'budgetId' },
              { name: 'budgetCode' },
              { name: 'inputQuantity' },
              { name: 'inputUnitPrice' },
              { name: 'inputUnit' },
              { name: 'outputQuantity' },
              { name: 'outputUnitPrice' },
              { name: 'outputUnit' },
              { name: 'adjustedOutputQuantity' },
              { name: 'performanceRatio' },
              { name: 'locations' },
              { name: 'createdAt' },
              { name: 'updatedAt' }
            ]
          when 'time-sheet'
            [
              { name: 'id' },
              { name: 'trackingItemInstanceId' },
              { name: 'startDate', type: 'date_time' },
              { name: 'endDate', type: 'date_time' },
              { name: 'inputUnit', type: 'integer' },
              { name: 'inputQuantity', type: 'integer' },
              { name: 'outputUnit', type: 'integer' },
              { name: 'outputQuantity', type: 'integer' },
              { name: 'creatorId' },
              { name: 'changedBy' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'updatedAt', type: 'date_time' }
            ]
          else
            []
          end
        when 'form'
          [
            { name: 'id' },
            { name: 'status' },
            { name: 'formNum', label: 'Form Number' },
            { name: 'formDate' },
            { name: 'assigneeId' },
            { name: 'assigneeId' },
            { name: 'updatedAt', type: 'date_time' },
            { name: 'createdBy' },
            { name: 'notes' },
            { name: 'description' },
            { name: 'pdfUrl' },
            { name: 'formTemplate', type: 'object', properties: [
              { name: 'id' },
              { name: 'name' },
              { name: 'status' },
              { name: 'templateType' }
            ]},
            { name: 'pdfValues', type: 'array', of: 'object', properties: [
              { name: 'name' },
              { name: 'value' }
            ]},
            { name: 'tabularValues', type: 'object', properties: [
              { name: 'worklogEntries', type: 'array', of: 'object', properties: [
                { name: 'id' },
                { name: 'deleted', type: 'boolean' },
                { name: 'trade' },
                { name: 'timespan', type: 'integer' },
                { name: 'headcount', type: 'integer'  },
                { name: 'description' }
              ]},
              { name: 'materialsEntries', type: 'array', of: 'object', properties: [
                { name: 'id' },
                { name: 'deleted', type: 'boolean' },
                { name: 'item' },
                { name: 'quantity', type: 'number'  },
                { name: 'unit' },
                { name: 'description' }
              ]},
              { name: 'equipmentEntries', type: 'array', of: 'object', properties: [
                { name: 'id' },
                { name: 'deleted', type: 'boolean' },
                { name: 'item' },
                { name: 'timespan', type: 'integer'  },
                { name: 'quantity', type: 'number'  },
                { name: 'description' }
              ]}
            ]},
            { name: 'customValues', type: 'array', of: 'object', properties: [
              { name: 'fieldId' },
              { name: 'sectionLabel' },
              { name: 'itemLabel' },
              { name: 'valueName' },
              { name: 'toggleVal' },
              { name: 'textVal' },
              { name: 'arrayVal' },
              { name: 'numberVal', type: 'integer' },
              { name: 'choiceVal' },
              { name: 'dateVal' },
              { name: 'svgVal' },
              { name: 'notes' }
            ]},
            { name: 'weather', type: 'object', properties: [
              { name: 'summaryKey' },
              { name: 'precipitationAccumulation' },
              { name: 'precipitationAccumulationUnit' },
              { name: 'temperatureMin' },
              { name: 'temperatureMax' },
              { name: 'temperatureUnit' },
              { name: 'humidity' },
              { name: 'windSpeed' },
              { name: 'windGust' },
              { name: 'speedUnit' },
              { name: 'windBearing' },
              { name: 'hourlyWeather', type: 'array', of: 'object', properties: [
                { name: 'id' },
                { name: 'hour' },
                { name: 'temp' },
                { name: 'windSpeed' },
                { name: 'windBearing' },
                { name: 'humidity' },
                { name: 'fetchedAt', type: 'date_time' },
                { name: 'createdAt', type: 'date_time' },
                { name: 'updatedAt', type: 'date_time' }
              ]}
            ]}
          ]
        when 'issue'
            [
                {
                    "type": "string",
                    "name": "id",
                    "label": "Issue ID"
                },
                {
                    "type": "number",
                    "name": "displayId"
                },
                {
                    "type": "string",
                    "name": "rootCauseId"
                },
                {
                    "type": "string",
                    "name": "title"
                },
                {
                    "type": "string",
                    "name": "description"
                },
                {
                    "type": "string",
                    "name": "issueTypeId"
                },
                {
                    "type": "string",
                    "name": "issueSubtypeId"
                },
                {
                    "type": "string",
                    "name": "status"
                },
                {
                    "type": "string",
                    "name": "assignedTo"
                },
                {
                    "type": "string",
                    "name": "assignedToType"
                },
                {
                    "type": "string",
                    "name": "dueDate"
                },
                {
                    "type": "string",
                    "name": "startDate"
                },
                {
                    "type": "string",
                    "name": "locationId"
                },
                {
                    "type": "string",
                    "name": "locationDetails"
                },
                {
                    "type": "string",
                    "name": "snapshotUrn"
                },
                {
                    "type": "boolean",
                    "name": "deleted"
                },
                {
                    "type": "string",
                    "name": "ownerId"
                },
                {
                    "properties":
                    [
                        {
                            "type": "string",
                            "name": "response"
                        },
                        {
                            "type": "string",
                            "name": "respondedAt"
                        },
                        {
                            "type": "string",
                            "name": "respondedBy"
                        }
                    ],
                    "type": "object",
                    "name": "officialResponse"
                },
                {
                    "name": "permittedAttributes",
                    "type": "array",
                    "of": "string",
                },
                {
                    "name": "permittedActions",
                    "type": "array",
                    "of": "string",
                },
                {
                    "type": "boolean",
                    "name": "published"
                },
                {
                    "type": "number",
                    "name": "commentCount"
                },
                {
                    "type": "number",
                    "name": "attachmentCount"
                },
                {
                    "type": "string",
                    "name": "openedBy"
                },
                {
                    "type": "date_time",
                    "name": "openedAt"
                },
                {
                    "type": "string",
                    "name": "closedBy"
                },
                {
                    "type": "date_time",
                    "name": "closedAt"
                },
                {
                    "type": "string",
                    "name": "createdBy"
                },
                {
                    "type": "date_time",
                    "name": "createdAt"
                },
                {
                    "type": "string",
                    "name": "updatedBy"
                },
                {
                    "type": "date_time",
                    "name": "updatedAt"
                },
                {
                    "type": "string",
                    "name": "issueTemplateId"
                },
                {
                    "name": "customAttributes",
                    "type": "array",
                    "of": "object",
                    "properties":
                    [
                        {
                            "type": "string",
                            "name": "attributeDefinitionId"
                        },
                        {
                            "type": "string",
                            "name": "value"
                        },
                        {
                            "type": "string",
                            "name": "type"
                        },
                        {
                            "type": "string",
                            "name": "title"
                        }
                    ]
                },
                {
                    "name": "permittedStatuses",
                    "type": "array",
                    "of": "string",
                }
            ]
        when 'rfi'
          [
            { name: 'id', label: 'RFI ID' },
            { name: 'customIdentifier' },
            { name: 'title' },
            { name: 'question' },
            { name: 'status' },
            { name: 'assignedTo' },
            { name: 'assignedToType' },
            { name: 'dueDate', type: 'date_time' },
            { name: 'createdBy' },
            { name: 'createdAt', type: 'date_time' },
            { name: 'updatedBy' },
            { name: 'updatedAt', type: 'date_time' },
            { name: 'suggestedAnswer' },
            { name: 'officialResponse' },
            { name: 'respondedAt', type: 'date_time' },
            { name: 'respondedBy' },
            { name: 'costImpact' },
            { name: 'scheduleImpact' },
            { name: 'priority' },
            { name: 'reference' },
            { name: 'managerId' },
            { name: 'architectId' },
            { name: 'reviewerId' },
            { name: 'attachmentsCount' },
            { name: 'commentsCount' },
            { name: 'location', type: 'object', properties: [
              { name: 'description' }
            ]},
            { name: 'discipline', type: 'array', of: 'string' },
            { name: 'category', type: 'array', of: 'string' },
            { name: 'coReviewers', type: 'array', of: 'string' },
            { name: 'distributionList', type: 'array', of: 'string' }
          ]
        when 'rfi_comment'
          [
            { name: 'id', label: 'Comment ID' },
            { name: 'rfiId' },
            { name: 'body' },
            { name: 'createdBy' },
            { name: 'createdAt', type: 'date_time' },
            { name: 'updatedAt', type: 'date_time' }
          ]
        when 'rfi_reference'
          [
            { name: 'id' },
            { name: 'createdOn', type: 'date_time' },
            { name: 'isReadOnly', type: 'boolean'},
            { name: 'isService', type: 'boolean'},
            { name: 'isDeleted', type: 'boolean'},
            { name: 'deletedOn', type: 'date_time'},
            { name: 'entities', type: 'array', of: 'object', properties: [
              { name: 'id' },
              { name: 'type' },
              { name: 'domain' },
              { name: 'createdOn', type: 'date_time' }
            ]}
          ]
        when 'takeoff'
          case config_fields['takeoff_object']
          when 'takeoff_package'
            [
              { name: 'id', label: 'ID' },
              { name: 'name' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'createdBy' },
              { name: 'createdByName' },
              { name: 'updatedAt', type: 'date_time' },
              { name: 'updatedBy' },
              { name: 'updatedByName' }
            ]
          when 'takeoff_type'
            [
              { name: 'id', label: 'Takeoff Type ID' },
              { name: 'name' },
              { name: 'description' },
              { name: 'color' },
              { name: 'borderColor' },
              { name: 'shapeType' },
              { name: 'countMarkerSize', type: 'number' },
              { name: 'tool' },
              { name: 'propertyDefinitions', type: 'object', properties: [
                { name: 'name' },
                { name: 'unitOfMeasure' },
                { name: 'value', type: 'number' },
                { name: 'valueLocation' }
              ]},
              { name: 'modelMappings', type: 'object', properties: [
                { name: 'name' },
                { name: 'mappingExpression' },
              ]},
              { name: 'primaryQuantityDefinition', type: 'object', properties: [
                { name: 'outputName' },
                { name: 'classificationCodeOne' },
                { name: 'classificationCodeTwo' },
                { name: 'expression' },
                { name: 'unitOfMeasure' }
              ]},
              { name: 'secondaryQuantityDefinition', type: 'object', properties: [
                { name: 'outputName' },
                { name: 'classificationCodeOne' },
                { name: 'classificationCodeTwo' },
                { name: 'expression' },
                { name: 'unitOfMeasure' }
              ]},
              { name: 'createdAt', type: 'date_time' },
              { name: 'createdBy' },
              { name: 'createdByName' },
              { name: 'updatedAt', type: 'date_time' },
              { name: 'updatedBy' },
              { name: 'updatedByName' }
            ]
          when 'takeoff_item'
            [
              { name: 'id', label: 'Takeoff Item ID' },
              { name: 'takeoffTypeId', label: 'Takeoff Type ID' },
              { name: 'type' },
              { name: 'objectName' },
              { name: 'geometry' },
              { name: 'objectId', type: 'number' },
              { name: 'propertyValues', type: 'object', properties: [
                { name: 'name' },
                { name: 'unitOfMeasure' },
                { name: 'source' },
                { name: 'number', type: 'number' },
                { name: 'string' },
                { name: 'valueLocation' }
              ]},
              { name: 'primaryQuantity', type: 'object', properties: [
                { name: 'outputName' },
                { name: 'classificationCodeOne' },
                { name: 'classificationCodeTwo' },
                { name: 'quantity', type: 'number' },
                { name: 'unitOfMeasure' }
              ]},
              { name: 'secondaryQuantities', type: 'object', properties: [
                { name: 'outputName' },
                { name: 'classificationCodeOne' },
                { name: 'classificationCodeTwo' },
                { name: 'quantity', type: 'number' },
                { name: 'unitOfMeasure' }
              ]},
              { name: 'contentView', type: 'object', properties: [
                { name: 'id' },
                { name: 'version', type: 'object', properties: [
                  { name: 'string' }
              ]},
              ]},
              { name: 'locationId' },
              { name: 'createdAt', type: 'date_time' },
              { name: 'createdBy' },
              { name: 'createdByName' },
              { name: 'updatedAt', type: 'date_time' },
              { name: 'updatedBy' },
              { name: 'updatedByName' }
            ]
          when 'classification_system'
            [
              { name: 'id', label: 'Classification System ID' },
              { name: 'name' },
              { name: 'type' },
              { name: 'sourceType' }
            ]
          when 'classification'
            [
              { name: 'code' },
              { name: 'parentCode' },
              { name: 'description' },
              { name: 'measurementType'}
            ]
          else
            []
          end
        when 'user'
          [
            { name: 'id' },
            { name: 'email' },
            { name: 'name' },
            { name: 'firstName' },
            { name: 'lastName' },
            { name: 'autodeskId' },
            { name: 'addressLine1' },
            { name: 'addressLine2' },
            { name: 'stateOrProvince' },
            { name: 'postalCode' },
            { name: 'country' },
            { name: 'imageUrl' },
            { name: 'phone' },
            { name: 'jobTitle' },
            { name: 'industry' },
            { name: 'aboutMe' },
            { name: 'companyId' },
            { name: 'status' },
            { name: 'addedOn', type: 'date_time' }
          ]
        when 'webhook'
          [

          ]
        when 'dm.version.added', 'dm.version.modified', 'dm.lineage.updated'
          [
            {
              name: 'payload',
              label: 'Document',
              type: 'object',
              properties: [
                { name: 'lineageUrn', label: 'ID' },
                { name: 'name' },
                { name: 'version' },
                { name: 'ext', label: 'Extension' },
                { name: 'sizeInBytes', type: 'number' },
                { name: 'hidden', type: 'boolean' },
                { name: 'creator' },
                { name: 'createdTime', type: 'date_time' },
                { name: 'modifiedBy' },
                { name: 'modifiedTime', type: 'date_time' },
                { name: 'parentFolderUrn' },
                { name: 'project', label: 'Project ID' },
                { name: 'tenant', label: 'Tenant ID' },
                { name: 'context', type: 'object', properties: [
                  { name: 'operation' }
                ]},
                { name: 'ancestors', type: 'array', of: 'object', properties: [
                  { name: 'name' },
                  { name: 'urn' }
                ]}
              ]
            },
            {
              name: 'hook',
              label: 'Event',
              type: 'object',
              properties: [
                { name: 'event' },
                { name: 'hookId' },
                { name: 'projectId' },
                { name: 'hubId' },
                { name: 'scope', type: 'object', properties: [
                  { name: 'folder' }
                ]},
                { name: 'createdDate', type: 'date_time' },
                { name: 'lastUpdatedDate', type: 'date_time' }
              ]
            }
          ]
        when 'dm.folder.added', 'dm.folder.modified', 'dm.folder.moved'
          [
            {
              name: 'payload',
              label: 'Folder',
              type: 'object',
              properties: [
                { name: 'lineageUrn', label: 'ID' },
                { name: 'name' },
                { name: 'folderAggregatePath' },
                { name: 'hidden', type: 'boolean' },
                { name: 'creator' },
                { name: 'createdTime', type: 'date_time' },
                { name: 'modifiedBy' },
                { name: 'modifiedTime', type: 'date_time' },
                { name: 'parentFolderUrn' },
                { name: 'project', label: 'Project ID' },
                { name: 'tenant', label: 'Tenant ID' },
                { name: 'context', type: 'object', properties: [
                  { name: 'operation' }
                ]},
                { name: 'ancestors', type: 'array', of: 'object', properties: [
                  { name: 'name' },
                  { name: 'urn' }
                ]}
              ]
            },
            {
              name: 'hook',
              label: 'Event',
              type: 'object',
              properties: [
                { name: 'event' },
                { name: 'hookId' },
                { name: 'projectId' },
                { name: 'hubId' },
                { name: 'scope', type: 'object', properties: [
                  { name: 'folder' }
                ]},
                { name: 'createdDate', type: 'date_time' },
                { name: 'lastUpdatedDate', type: 'date_time' }
              ]
            }
          ]
        else
          []
        end
      end
    },

    custom_action_input: {
      fields: lambda do |_connection, config_fields|
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
            'https://developer.api.autodesk.com' \
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
    }
  },

  actions: {
    custom_action: {
      subtitle: 'Build your own Autodesk Construction Cloud action with a HTTP request',

      description: lambda do |object_value, _object_label|
        "<span class='provider'>" \
        "#{object_value[:action_name] || 'Custom action'}</span> in " \
        "<span class='provider'>Autodesk Construction Cloud</span>"
      end,

      help: {
        body: 'Build your own Autodesk Construction Cloud action with a HTTP request. ' \
        'The request will be authorized with your Autodesk Construction Cloud connection.',
        learn_more_url: 'https://forge.autodesk.com/',
        learn_more_text: 'Autodesk Construction Cloud API documentation'
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
          pick_list: %w[get post put patch options delete]
            .map { |verb| [verb.upcase, verb] }
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
                  end.headers(request_headers)
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
          end
          .after_error_response(/.*/) do |code, body, headers, message|
            error({ code: code, message: message, body: body, headers: headers }
              .to_json)
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

    create_object: {
      title: 'Create object in a project',
        description: lambda do |_connection, objects|
          "Create <span class='provider'>#{objects['object']&.downcase || 'object'}</span> in a project in <span class='provider'>Autodesk Construction Cloud</span>"
        end,

        help: "Creates an object in a project.",

        config_fields: [
          {
            name: 'object',
            label: 'Object',
            optional: false,
            pick_list: 'create_object_list',
            control_type: :select,
            hint: 'Select the object from picklist.'
          },
          {
            name: 'hub_id',
            label: 'Account name',
            control_type: 'select',
            pick_list: 'hub_list',
            optional: false,
            toggle_hint: 'Select account',
            toggle_field: {
              name: 'hub_id',
              label: 'Account ID',
              type: 'string',
              change_on_blur: true,
              control_type: 'text',
              toggle_hint: 'Enter account ID'
            }
          },
          {
            name: 'project_id',
            label: 'Project name',
            control_type: 'select',
            pick_list: 'project_list',
            pick_list_params: { hub_id: 'hub_id' },
            optional: false,
            toggle_hint: 'Select project',
            toggle_field: {
              name: 'project_id',
              label: 'Project ID',
              change_on_blur: true,
              type: 'string',
              control_type: 'text',
              toggle_hint: 'Enter project ID'
            }
          }
        ],

        input_fields: lambda do |object_definitions|
          object_definitions['create_object_input']
        end,

        execute: lambda do |_connection, input|
          hub_id = input.delete('hub_id')
          project_id = input.delete('project_id')
          object = input.delete('object')

          case object
          # start `create folder`
          when 'folder'
            payload = {
              'jsonapi' => {
                'version' => '1.0'
              },
              'data' => {
                'type'=> 'folders',
                'attributes'=> {
                  'name'=> input['name'],
                  'extension'=> {
                    'type' => 'folders:autodesk.bim360:Folder',
                    'version' => '1.0'
                  }
                },
                'relationships' => {
                  'parent' => {
                    'data' => {
                      'type' => 'folders',
                      'id' => input['folder_id']
                    }
                  }
                }
              }
            }

            response = post("/data/v1/projects/#{project_id}/folders").
                        payload(payload).
                        after_error_response(/.*/) do |_code, body, _header, message|
                          error("#{message}: #{body}")
                        end.merge(hub_id: hub_id, project_id: project_id)
          #end `create folder`

          when 'rfi'
            project_id = project_id.split('.').last
            input['status'] = 'draft'
            input['discipline'].present? ? input['discipline'] = (input['discipline']||'').split(',') : nil
            input['category'].present? ? input['category'] = (input['category']||'').split(',') : nil
            input['coReviewers'].present? ? input['coReviewers'] = (input['coReviewers']||'').split(',') : nil
            input['distributionList'].present? ? input['distributionList'] = (input['distributionList']||'').split(',') : nil

            response = post("/bim360/rfis/v2/containers/#{project_id}/#{object.pluralize}").
                        payload(input.compact).
                        after_error_response(/.*/) do |_code, body, _header, message|
                          error("#{message}: #{body}")
                        end.merge(hub_id: hub_id, project_id: project_id)

          when 'rfi_comment'
            project_id = project_id.split('.').last

            response = post("/bim360/rfis/v2/containers/#{project_id}/rfis/#{input.delete('id')}/comments").
                        payload(input).
                        after_error_response(/.*/) do |_code, body, _header, message|
                          error("#{message}: #{body}")
                        end.merge(hub_id: hub_id, project_id: project_id)

          when 'cost'
            project_id = project_id.split('.').last
            cost_object = input.delete('cost_object')

            case cost_object
            when 'attachment'
              attachment_folder = post("/cost/v1/containers/#{project_id}/attachment-folders").
                                  payload(
                                    associationId: input['associationId'],
                                    associationType: input['associationType']
                                  )&.dig('id')

              input['folderId'] = attachment_folder
              response = post("/cost/v1/containers/#{project_id}/attachments").
                          payload(input).
                          after_error_response(/.*/) do |_code, body, _header, message|
                            error("#{message}: #{body}")
                          end.merge(hub_id: hub_id, project_id: project_id)

            when 'change-order'
              change_order_type = input.delete('change_order_type')
              response = post("/cost/v1/containers/#{project_id}/#{cost_object.pluralize}/#{change_order_type}").
                        payload(input).
                        after_error_response(/.*/) do |_code, body, _header, message|
                          error("#{message}: #{body}")
                        end.merge(hub_id: hub_id, project_id: project_id)
            else
              response = post("/cost/v1/containers/#{project_id}/#{cost_object.pluralize}").
                        payload(input).
                        after_error_response(/.*/) do |_code, body, _header, message|
                          error("#{message}: #{body}")
                        end.merge(hub_id: hub_id, project_id: project_id)
            end

          when 'issue'
            project_id = project_id.split('.').last
            issue_type_id = input.delete('issueTypeId')
            response = post("/construction/issues/v1/projects/#{project_id}/issues").
                        payload(input.compact).
                        after_error_response(/.*/) do |_code, body, _header, message|
                          error("#{message}: #{body}")
                        end.merge(hub_id: hub_id, project_id: project_id)

          when 'webhook'
            hookAttributes = {}
            if input['hookAttribute'].present? && input['hookAttribute'].length > 0
              input['hookAttribute'].each do |i|
                key = i['key']
                value = i['value']
                hookAttributes[key] = value
              end
            end

            region = get("/project/v1/hubs/#{hub_id}").dig('data','attributes','region')
            payload = {
              'callbackUrl' => input['callbackUrl'],
              'scope' => {
                'folder' => input['folder_id']
              },
              'filter' => input['filter'],
              'hubId' => hub_id,
              'projectId' => project_id,
              'hookExpiry' => input['hookExpiry'],
              'hookAttribute' => hookAttributes
            }

            post("/webhooks/v1/systems/data/events/#{input['event']}/hooks").
              payload(payload).
              headers({ 'x-ads-region': region }).
              after_error_response(/.*/) do |_code, body, _header, message|
                error("#{message}: #{body}")
              end.merge(hub_id: hub_id, project_id: project_id)
          end

        end,

        output_fields: lambda do |object_definitions|
          [
            { name: 'hub_id', label: 'Account ID' },
            { name: 'project_id' }
          ]
          .concat(object_definitions['object_output_response'])
        end,

        sample_output: lambda do |_connection, input|
          case input['object']
          when 'folder'
            get("/project/v1/hubs/#{input['hub_id']}/projects/#{input['project_id']}/topFolders")&.
            dig('data', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          when 'item'
            get("/data/v1/projects/#{input['project_id']}/folders/#{input['folder_id']}/search?page[limit]=1")&.
            dig('included', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          when 'rfi'
            get("/bim360/rfis/v2/containers/#{input['project_id'].split('.').last}/rfis?limit=1")&.
            dig('results', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          when 'cost'
            project_id = input['project_id'].split('.').last

            case input['cost_object']
            when 'attachment'
              # use example from Forge
              {
                hub_id: input['hub_id'],
                project_id: input['project_id'],
                id: 'F2D2ED17-C763-465B-8FAB-251C5A35D42F',
                folderId: '8E34872D-A56F-4096-B675-476F50F4EF51',
                urn: 'urn:adsk.wipprod:fs.file:vf.PMbRnoPZR2mKDhau2uw4SQ?version=1',
                type: 'Upload',
                name: 'Architecture',
                associationId: 'EDC42DF6-277A-436A-A50D-EF57F35E1248',
                associationType: 'Budget',
                createdAt: '2019-01-06T01:24:22.678Z',
                updatedAt: '2019-09-05T01:00:12.989Z'
              }
            when 'change-order'
              get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/#{input['change_order_type']}?limit=1")&.
              dig('results', 0)&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            when 'payment'
              get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/?filter[associationType]=#{input['payment_type']}&limit=1")&.
              dig('results', 0)&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            else
              get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}?limit=1")&.
              dig('results')[0]&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            end
          end
        end
    },

    update_object: {
      title: 'Update object in a project',
        description: lambda do |_connection, objects|
          "Update <span class='provider'>#{objects['object']&.downcase || 'object'}</span> in a project in <span class='provider'>Autodesk Construction Cloud</span>"
        end,

        help: "Updates an object in a project.",

        config_fields: [
          {
            name: 'object',
            label: 'Object',
            optional: false,
            pick_list: 'update_object_list',
            control_type: :select,
            hint: 'Select the object from picklist.'
          },
          {
            name: 'hub_id',
            label: 'Account name',
            control_type: 'select',
            pick_list: 'hub_list',
            optional: false,
            toggle_hint: 'Select account',
            toggle_field: {
              name: 'hub_id',
              label: 'Account ID',
              type: 'string',
              change_on_blur: true,
              control_type: 'text',
              toggle_hint: 'Enter account ID'
            }
          },
          {
            name: 'project_id',
            label: 'Project name',
            control_type: 'select',
            pick_list: 'project_list',
            pick_list_params: { hub_id: 'hub_id' },
            optional: false,
            toggle_hint: 'Select project',
            toggle_field: {
              name: 'project_id',
              label: 'Project ID',
              change_on_blur: true,
              type: 'string',
              control_type: 'text',
              toggle_hint: 'Enter project ID'
            }
          }
        ],

        input_fields: lambda do |object_definitions|
          object_definitions['update_object_input']
        end,

        execute: lambda do |_connection, input|
          hub_id = input.delete('hub_id')
          project_id = input.delete('project_id')
          object = input.delete('object')

          case object
          # start `update folder`
          when 'folder'
            payload = {
              'jsonapi' => {
                'version' => '1.0'
              },
              'data' => {
                'id' => input['folder_id'],
                'type' => 'folders',
                'attributes' => {
                  'name' => input['name'],
                  'displayName' => input['name']
                }
              }
            }

            response = patch("/data/v1/projects/#{project_id}/#{input['object'].pluralize}/#{input['folder_id']}").
                        payload(payload).
                        after_error_response(/.*/) do |_code, body, _header, message|
                          error("#{message}: #{body}")
                        end.merge(hub_id: hub_id, project_id: project_id)
          # end `update folder`

          # start 'update document'
          when 'item'
          item_id = input['item_id']
            payload = {
              'jsonapi' => {
                'version' => '1.0'
              },
              'data' => {
                'type' => 'versions',
                'attributes' => {
                  'name' => input['name']
                }
              }
            }
            version_id = get("/data/v1/projects/#{project_id}/items/#{item_id}").
            			dig('data','relationships','tip','data','id')
            response = post("/data/v1/projects/#{project_id}/versions?copyFrom=#{version_id.encode_url}").
                        payload(payload).
                        after_error_response(/.*/) do |_code, body, _header, message|
                          error("#{message}: #{body}")
                        end.merge(hub_id: hub_id, project_id: project_id)

          when 'rfi'
            project_id = project_id.split('.').last
            input['discipline'].present? ? input['discipline'] = (input['discipline']||'').split(',') : nil
            input['category'].present? ? input['category'] = (input['category']||'').split(',') : nil
            input['coReviewers'].present? ? input['coReviewers'] = (input['coReviewers']||'').split(',') : nil
            input['distributionList'].present? ? input['distributionList'] = (input['distributionList']||'').split(',') : nil

            response = patch("/bim360/rfis/v2/containers/#{project_id}/#{object.pluralize}/#{input.delete('id')}").
                        payload(input.compact).
                        after_error_response(/.*/) do |_code, body, _header, message|
                          error("#{message}: #{body}")
                        end.merge(hub_id: hub_id, project_id: project_id)

          when 'cost'
            project_id = project_id.split('.').last
            cost_object = input.delete('cost_object')

            case cost_object
            when 'change-order'
              response = patch("/cost/v1/containers/#{project_id}/#{cost_object.pluralize}/#{input.delete('change_order_type')}/#{input.delete('id')}").
                          payload(input).
                          after_error_response(/.*/) do |_code, body, _header, message|
                            error("#{message}: #{body}")
                          end.merge(hub_id: hub_id, project_id: project_id)
            else
              response = patch("/cost/v1/containers/#{project_id}/#{cost_object.pluralize}/#{input.delete('id')}").
                          payload(input).
                          after_error_response(/.*/) do |_code, body, _header, message|
                            error("#{message}: #{body}")
                          end.merge(hub_id: hub_id, project_id: project_id)
            end

          when 'issue'
              project_id = project_id.split('.').last
              issue_type_id = input.delete('nissueTypeId')
              response = patch("/construction/issues/v1/projects/#{project_id}/issues/#{input.delete('id')}").
                          payload(input).
                          after_error_response(/.*/) do |_code, body, _header, message|
                            error("#{message}: #{body}")
                          end.merge(hub_id: hub_id, project_id: project_id)
          end

        end,

        output_fields: lambda do |object_definitions|
          [
            { name: 'hub_id', label: 'Account ID' },
            { name: 'project_id' }
          ]
          .concat(object_definitions['object_output_response'])
        end,

        sample_output: lambda do |_connection, input|
          case input['object']
          when 'folder'
            get("/project/v1/hubs/#{input['hub_id']}/projects/#{input['project_id']}/topFolders")&.
            dig('data', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          when 'item'
            get("/data/v1/projects/#{input['project_id']}/folders/#{input['folder_id']}/search?page[limit]=1")&.
            dig('included', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          when 'rfi'
            get("/bim360/rfis/v2/containers/#{input['project_id'].split('.').last}/rfis?limit=1")&.
            dig('results', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          when 'cost'
            project_id = input['project_id'].split('.').last

            case input['cost_object']
            when 'change-order'
              get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/#{input['change_order_type']}?limit=1")&.
              dig('results', 0)&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            else
              get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}?limit=1")&.
              dig('results')[0]&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            end
          end
        end
    },

    get_object: {
      title: 'Get object in a project',
        description: lambda do |_connection, objects|
          "Get <span class='provider'>#{objects['object']&.downcase || 'object'}</span> in <span class='provider'>Autodesk Construction Cloud</span>"
        end,

        help: "Retrieve an object in a project.",

        config_fields: [
          {
            name: 'object',
            label: 'Object',
            optional: false,
            pick_list: 'get_object_list',
            control_type: :select,
            hint: 'Select the object from picklist.'
          },
          {
            name: 'hub_id',
            label: 'Account name',
            control_type: 'select',
            pick_list: 'hub_list',
            optional: false,
            toggle_hint: 'Select account',
            toggle_field: {
              name: 'hub_id',
              label: 'Account ID',
              type: 'string',
              change_on_blur: true,
              control_type: 'text',
              toggle_hint: 'Enter account ID'
            }
          },
          {
            name: 'project_id',
            label: 'Project name',
            control_type: 'select',
            pick_list: 'project_list',
            pick_list_params: { hub_id: 'hub_id' },
            optional: false,
            toggle_hint: 'Select project',
            toggle_field: {
              name: 'project_id',
              label: 'Project ID',
              change_on_blur: true,
              type: 'string',
              control_type: 'text',
              toggle_hint: 'Enter project ID'
            }
          }
        ],

        input_fields: lambda do |object_definitions|
          object_definitions['get_object_input']
        end,

        execute: lambda do |_connection, input|
          hub_id = input.delete('hub_id')
          project_id = input.delete('project_id')

          case input['object']
          when 'project'
            response = get("/project/v1/hubs/#{hub_id}/projects/#{project_id}")&.
                        dig('data')&.
                        merge(hub_id: hub_id, project_id: project_id)

          when 'folder'
            response = get("/data/v1/projects/#{project_id}/#{input['object'].pluralize}/#{input['folder_id']}")&.
                        dig('data')&.
                        merge(hub_id: hub_id, project_id: project_id)

          when 'form'
            response = get("/construction/forms/v1/projects/#{project_id}/#{input['object'].pluralize}", {ids: input['id']})&.
                        dig('data')[0]&.
                        merge(hub_id: hub_id, project_id: project_id)

          when 'item'
            response = get("/data/v1/projects/#{project_id}/#{input['object'].pluralize}/#{input['item_id']}?includePathInProject=true")&.
                        dig('data')&.
                        merge(hub_id: hub_id, project_id: project_id)
          when 'issue'
            response = get("/construction/issues/v1/projects/#{project_id.split('.').last}/issues/#{input['id']}")&.
                        merge(hub_id: hub_id, project_id: project_id)

          when 'rfi'
            response = get("/bim360/rfis/v2/containers/#{project_id.split('.').last}/rfis/#{input['id']}")&.
                        merge(hub_id: hub_id, project_id: project_id)

          when 'user'
            response = get("/construction/admin/v1/projects/#{project_id.split('.').last}/users/#{input['id']}")&.
                        merge(hub_id: hub_id, project_id: project_id)

          when 'cost'
            project_id = project_id.split('.').last

            case input['cost_object']
            when 'change-order'
              response = get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/#{input['change_order_type']}/#{input['id']}")&.
                        merge(hub_id: hub_id, project_id: project_id)
            when 'expense'
              response = get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/#{input['id']}?include=expenseItems,mainContract,attributes")&.
                        merge(hub_id: hub_id, project_id: project_id)
            else
              response = get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/#{input['id']}")&.
                        merge(hub_id: hub_id, project_id: project_id)
            end

          when 'takeoff'
            case input['takeoff_object']
            when 'takeoff_package'
              response = get("/construction/takeoff/v1/projects/#{project_id}/packages/#{input['id']}")&.
                          merge(hub_id: hub_id, project_id: project_id)
            when 'takeoff_type'
              response = get("/construction/takeoff/v1/projects/#{project_id}/packages/#{input['package_id']}/takeoff-types/#{input['id']}")&.
                          merge(hub_id: hub_id, project_id: project_id)
            when 'takeoff_item'
              response = get("/construction/takeoff/v1/projects/#{project_id}/packages/#{input['package_id']}/takeoff-items/#{input['id']}")&.
              merge(hub_id: hub_id, project_id: project_id)
            when 'classification_system'
              response = get("/construction/takeoff/v1/projects/#{project_id}/classifiction-systems/#{input['id']}")&.
              merge(hub_id: hub_id, project_id: project_id)
            end

          end
        end,

        output_fields: lambda do |object_definitions|
          [
            { name: 'hub_id', label: 'Account ID' },
            { name: 'project_id' }
          ]
          .concat(object_definitions['object_output_response'])
        end,

        sample_output: lambda do |_connection, input|
          # call('get_sample_output', input)
          # start case
          case input['object']
          when 'project'
            get("/project/v1/hubs/#{input['hub_id']}/projects?page[limit]=1")&.
            dig('data', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          when 'folder'
            get("/project/v1/hubs/#{input['hub_id']}/projects/#{input['project_id']}/topFolders")&.
            dig('data', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          when 'item'
            get("/data/v1/projects/#{input['project_id']}/folders/#{input['folder_id']}/search?page[limit]=1")&.
            dig('included', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          when 'rfi'
            get("/bim360/rfis/v2/containers/#{input['project_id'].split('.').last}/rfis?limit=1")&.
            dig('results', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])

          when 'cost'
            project_id = input['project_id'].split('.').last

            case input['cost_object']
            when 'change-order'
              get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/#{input['change_order_type']}?limit=1")&.
              dig('results', 0)&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            when 'payment'
              get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/?filter[associationType]=#{input['payment_type']}&limit=1")&.
              dig('results', 0)&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            else
              get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}?limit=1")&.
              dig('results')[0]&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            end

          when 'takeoff'
            case input['takeoff_object']
            when 'takeoff_package'
              get("/v1/projects/#{input['project_id']}/packages?limit=1")&.
              dig('results', 0)&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            when 'takeoff_type'
              takeoffpackage_id = get("/v1/projects/#{input['project_id']}/packages")&.
              dig(0, 'id')

              get("/v1/projects/#{input['project_id']}/packages/#{takeoffpackage_id}/takeoff-types")&.
              dig(0)&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            when 'takeoff_item'
              takeoffpackage_id = get("/v1/projects/#{input['project_id']}/packages")&.
              dig(0, 'id')
              get("/v1/projects/#{input['project_id']}/packages/#{takeoffpackage_id}/takeoff-items")&.
              dig(0)&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            when 'classification_system'
              get("/v1/projects/#{input['project_id']}/classification-systems")&.
              dig(0)&.
              merge(hub_id: input['hub_id'], project_id: input['project_id'])
            end

          end
          # end case
        end,

        retry_on_response: [500, /error/],
        retry_on_request: ['GET'],
        max_retries: 3

    },

    download_object: {
      title: 'Download object in a project',
        description: lambda do |_connection, objects|
          "Download <span class='provider'>#{objects['object']&.downcase || 'object'}</span> in <span class='provider'>Autodesk Construction Cloud</span>"
        end,

        help: "Download an object in a project.",

        config_fields: [
          {
            name: 'object',
            label: 'Object',
            optional: false,
            pick_list: 'download_object_list',
            control_type: :select,
            hint: 'Select the object from picklist.'
          },
          {
            name: 'hub_id',
            label: 'Account name',
            control_type: 'select',
            pick_list: 'hub_list',
            optional: false,
            toggle_hint: 'Select account',
            toggle_field: {
              name: 'hub_id',
              label: 'Account ID',
              type: 'string',
              change_on_blur: true,
              control_type: 'text',
              toggle_hint: 'Enter account ID'
            }
          },
          {
            name: 'project_id',
            label: 'Project name',
            control_type: 'select',
            pick_list: 'project_list',
            pick_list_params: { hub_id: 'hub_id' },
            optional: false,
            toggle_hint: 'Select project',
            toggle_field: {
              name: 'project_id',
              label: 'Project ID',
              change_on_blur: true,
              type: 'string',
              control_type: 'text',
              toggle_hint: 'Enter project ID'
            }
          }
        ],

        input_fields: lambda do |object_definitions|
          object_definitions['download_object_input']
        end,

        execute: lambda do |_connection, input|
          hub_id = input.delete('hub_id')
          project_id = input.delete('project_id')

          case input['object']
          when 'item'
            file_url = get("/data/v1/projects/#{project_id}/items/#{input['item_id']}")&.
                         dig('included', 0, 'relationships', 'storage', 'meta', 'link', 'href')
            file_url = get("#{file_url.split('?').first}/signeds3download")
            if file_url.present? && file_url['status'] == 'complete'
              get(file_url['url']).headers(
                              'Accept-Encoding': 'Accept-Encoding:gzip',
                              'Accept': '*/*'
                            ).
                            response_format_raw.
                            after_response do |code, body, headers|
                              {
                                file_content: body,
                                file_size: headers['content_length']
                              }
                            end
            else
              error('File does not exist')
            end
          end
        end,

        output_fields: lambda do |object_definitions|
          [
            { name: 'file_content' },
            { name: 'file_size' }
          ]
        end,

        sample_output: lambda do |_connection, input|
          {
            'file_content': '<file-content>',
            'file_size': '12345'
          }
        end

    },

    search_object: {
      title: 'Search for objects in a project',
        description: lambda do |_connection, objects|
          "Search for <span class='provider'>#{objects['object']&.downcase&.pluralize || 'object'}</span> in a project in <span class='provider'>Autodesk Construction Cloud</span>"
        end,

        help: "Search for objects in a project.",

        config_fields: [
          {
            name: 'object',
            label: 'Object',
            optional: false,
            pick_list: 'search_object_list',
            control_type: :select,
            hint: 'Select the object from picklist.'
          },
          {
            name: 'hub_id',
            label: 'Account name',
            control_type: 'select',
            pick_list: 'hub_list',
            optional: false,
            toggle_hint: 'Select account',
            toggle_field: {
              name: 'hub_id',
              label: 'Account ID',
              type: 'string',
              change_on_blur: true,
              control_type: 'text',
              toggle_hint: 'Enter account ID'
            }
          },
          {
            name: 'project_id',
            label: 'Project name',
            control_type: 'select',
            pick_list: 'project_list',
            pick_list_params: { hub_id: 'hub_id' },
            optional: false,
            toggle_hint: 'Select project',
            toggle_field: {
              name: 'project_id',
              label: 'Project ID',
              change_on_blur: true,
              type: 'string',
              control_type: 'text',
              toggle_hint: 'Enter project ID'
            }
          }
        ],

        input_fields: lambda do |object_definitions|
          object_definitions['search_object_input']
        end,

        execute: lambda do |_connection, input|
          hub_id = input.delete('hub_id')
          project_id = input.delete('project_id')
          object = input.delete('object')

          case object
          when 'item'
            object = input.delete('object')
            folder_id = input.delete('folder_id')
            filters = ''
            filters = input['file_type'].present? ? filters + "filter[fileType]=#{input['file_type']}&" : filters
            filters = input['file_name'].present? ? filters + "filter[attributes.displayName]-contains=#{input['file_name']}&" : filters
            filters = input['updated_after'].present? ? filters + "filter[lastModifiedTime]-ge=#{input['updated_after'].to_time.utc.iso8601}&" : filters
            filters = input['filters'].present? ? filters + "#{input['filters']}" : filters

            get("/data/v1/projects/#{project_id}/folders/#{folder_id}/search?#{filters}")&.
            merge(hub_id: hub_id, project_id: project_id)

          when 'issue'
            project_id = project_id.split('.').last
            filter_criteria = call('format_issue_search', input.compact)
            response = get("/construction/issues/v1/projects/#{project_id}/#{object.pluralize}", filter_criteria.compact)

            {
              results: response.dig('results'),
              pagination: response.dig('pagination'),
              hub_id: hub_id,
              project_id: project_id
            }

          when 'form'
            project_id = project_id.split('.').last
            # filter_criteria = call('format_issue_search', input.compact)
            response = get("/construction/forms/v1/projects/#{project_id}/#{object.pluralize}", input.compact)

            {
              results: response.dig('data'),
              pagination: response.dig('pagination'),
              hub_id: hub_id,
              project_id: project_id
            }

          when 'rfi'
            project_id = project_id.split('.').last
            filter_criteria = call('format_rfi_search', input)
            response = get("/bim360/rfis/v2/containers/#{project_id}/#{object.pluralize}", filter_criteria)

            {
              results: response.dig('results'),
              pagination: response.dig('pagination'),
              hub_id: hub_id,
              project_id: project_id
            }

          when 'rfi_comment'
            project_id = project_id.split('.').last

            response = get("/bim360/rfis/v2/containers/#{project_id}/rfis/#{input.delete('id')}/comments", input)

            {
              results: response['results'],
              pagination: response['pagination'],
              hub_id: hub_id,
              project_id: project_id
            }

          when 'rfi_reference'
            project_id = project_id.split('.').last

            entities = {
              'domain' => 'autodesk-bim360-rfi',
              'type' => 'rfi',
              'id' => input['id']
            }

            response = post("/bim360/relationship/v2/containers/#{project_id}/relationships:intersect").
                        params(input).
                        payload('entities' => [entities])

            {
              results: response.dig('relationships'),
              pagination: response.dig('page'),
              hub_id: hub_id,
              project_id: project_id
            }

          when 'cost'
            project_id = project_id.split('.').last
            cost_object = input.delete('cost_object')

            case cost_object
            when 'attachment', 'document'
              filter_criteria = call('format_cost_search', input.compact.except(:associationId, :associationType))
              filter_criteria['associationId'] = input['associationId']
              filter_criteria['associationType'] = input['associationType']
              results = get("/cost/v1/containers/#{project_id}/#{cost_object.pluralize}", filter_criteria)
              { results: results, hub_id: hub_id, project_id: project_id }

            when 'file-package'
              filter_criteria = call('format_cost_search', input.compact)
              results = get("/cost/v1/containers/#{project_id}/#{cost_object.pluralize}", filter_criteria)
              { results: results, hub_id: hub_id, project_id: project_id }

            when 'change-order'
              change_order_type = input.delete('change_order_type')
              filter_criteria = call('format_cost_search', input.compact)
              get("/cost/v1/containers/#{project_id}/#{cost_object.pluralize}/#{change_order_type}", filter_criteria)&.
              merge(hub_id: hub_id, project_id: project_id)
            when 'expense'
              filter_criteria = call('format_cost_search', input.compact)
              get("/cost/v1/containers/#{project_id}/#{cost_object.pluralize}?include=expenseItems,mainContract,attributes", filter_criteria)&.
              merge(hub_id: hub_id, project_id: project_id)
            else
              filter_criteria = call('format_cost_search', input.compact)
              get("/cost/v1/containers/#{project_id}/#{cost_object.pluralize}", filter_criteria)&.
              merge(hub_id: hub_id, project_id: project_id)
            end


          when 'takeoff'
            takeoff_object = input.delete('takeoff_object')

            case takeoff_object
            when 'takeoff_package'
              response = get("/construction/takeoff/v1/projects/#{project_id}/packages", input)
            when 'takeoff_item'
              response = get("/construction/takeoff/v1/projects/#{project_id}/packages/#{input.delete('package_id')}/takeoff-items", input)
            when 'takeoff_type'
              response = get("/construction/takeoff/v1/projects/#{project_id}/packages/#{input.delete('package_id')}/takeoff-types", input)
            when 'classification_system'
              response = get("/construction/takeoff/v1/projects/#{project_id}/classification-systems", input)
            when 'classification'
              response = get("/construction/takeoff/v1/projects/#{project_id}/classification-systems/#{input.delete('classification_id')}/classifications", input)
            end

          end
        end,

        output_fields: lambda do |object_definitions, _connection, config_fields|
          [
            { name: 'hub_id', label: 'Account ID' },
            { name: 'project_id' }
          ].concat(

            case config_fields['object']
            when 'item'
              [
                { name: 'included', label: 'Results', type: 'array',
                  of: 'object', properties: object_definitions['object_output_response'] }
              ]

            when 'issue'
              [
                { name: 'results', type: 'array',
                  of: 'object', properties: object_definitions['object_output_response'] },
                { name: 'pagination', type: 'object', properties: [
                  { name: 'limit', type: 'integer' },
                  { name: 'offset', type: 'integer' },
                  { name: 'totalResults', type: 'integer' },
                  { name: 'next' }
                ]}
              ]
            when 'form'
              [
                { name: 'results', type: 'array',
                  of: 'object', properties: object_definitions['object_output_response'] },
                { name: 'pagination', type: 'object', properties: [
                  { name: 'limit', type: 'integer' },
                  { name: 'offset', type: 'integer' },
                  { name: 'totalResults', type: 'integer' },
                  { name: 'nextUrl' }
                ]}
              ]

            when 'rfi'
              [
                { name: 'results', type: 'array',
                  of: 'object', properties: object_definitions['object_output_response'] },
                { name: 'pagination', type: 'object', properties: [
                  { name: 'limit', type: 'integer' },
                  { name: 'offset', type: 'integer' },
                  { name: 'totalResults', type: 'integer' }
                ]}
              ]
            when 'rfi_comment'
              [
                { name: 'results', type: 'array',
                  of: 'object', properties: object_definitions['object_output_response'] },
                { name: 'pagination', type: 'object', properties: [
                  { name: 'limit', type: 'integer' },
                  { name: 'offset', type: 'integer' },
                  { name: 'totalResults', type: 'integer' }
                ]}
              ]
            when 'rfi_reference'
              [
                { name: 'results', type: 'array',
                  of: 'object', properties: object_definitions['object_output_response'] },
                { name: 'pagination', type: 'object', properties: [
                  { name: 'continuationToken' },
                  { name: 'syncToken' }
                ]}
              ]
            when 'cost'
              [
                { name: 'results', type: 'array', of: 'object', properties: object_definitions['object_output_response'] }
              ].concat(
                if config_fields['cost_object'].present? && 'attachment document file-package'.exclude?(config_fields['cost_object'])
                  [
                    { name: 'pagination', type: 'object', properties: [
                      { name: 'limit', type: 'number' },
                      { name: 'offset', type: 'number' },
                      { name: 'totalResults', type: 'number' },
                      { name: 'nextUrl' }
                    ]}
                  ]
                else
                  []
                end
              )
            when 'takeoff'
              [
                { name: 'results', type: 'array',
                  of: 'object', properties: object_definitions['object_output_response'] },
                { name: 'pagination', type: 'object', properties: [
                  { name: 'limit', type: 'integer' },
                  { name: 'offset', type: 'integer' },
                  { name: 'totalResults', type: 'integer' },
                  { name: 'nextUrl' }
                ]}
              ]
            else
              []
            end
          )
        end,

        sample_output: lambda do |_connection, input|
          # start case
          case input['object']
          when 'item'
            results = get("/data/v1/projects/#{input['project_id']}/folders/#{input['folder_id']}/search?page[limit]=1")&.
                      dig('included')
            {
              hub_id: input['hub_id'],
              project_id: input['project_id'],
              included: results
            }
          when 'rfi'
            get("/bim360/rfis/v2/containers/#{input['project_id'].split('.').last}/rfis?limit=1")&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          when 'cost'
            project_id = input['project_id'].split('.').last

            case input['cost_object']
            when 'attachment'
              # use example from forge
              {
                hub_id: input['hub_id'],
                project_id: input['project_id'],
                results: [
                  {
                    id: 'F2D2ED17-C763-465B-8FAB-251C5A35D42F',
                    folderId: '8E34872D-A56F-4096-B675-476F50F4EF51',
                    urn: 'urn:adsk.wipprod:fs.file:vf.PMbRnoPZR2mKDhau2uw4SQ?version=1',
                    type: 'Upload',
                    name: 'Architecture',
                    associationId: 'EDC42DF6-277A-436A-A50D-EF57F35E1248',
                    associationType: 'Budget',
                    createdAt: '2019-01-06T01:24:22.678Z',
                    updatedAt: '2019-09-05T01:00:12.989Z'
                  }
                ]
              }
            when 'document'
              # use example from forge
              {
                hub_id: input['hub_id'],
                project_id: input['project_id'],
                results: [
                  {
                    id: '1df59db0-9484-11e8-a7ec-7ddae203e404',
                    templateId: '1df59db0-9484-11e8-a7ec-7ddae203e404',
                    recipientId: 'GF8XKPKWM38E',
                    signedBy: 'CED9LVTLHNXV',
                    urn: 'urn:adsk.wipprod:fs.file:vf.PMbRnoPZR2mKDhau2uw4SQ?version=1',
                    pdfUrn: 'urn:adsk.wipprod:fs.file:vf.PMbRnoPZR2mKDhau2uw4SQ?version=1',
                    signedUrn: 'urn:adsk.wipprod:fs.file:vf.PMbRnoPZR2mKDhau2uw4SQ?version=1',
                    status: 'Completed',
                    jobId: 1,
                    errorInfo: {
                      code: 'missingTemplate',
                      message: 'Could not generate the document because the template is invalid.',
                      detail: 'Got timeout for POST upload URL.'
                    },
                    associationId: 'EDC42DF6-277A-436A-A50D-EF57F35E1248',
                    associationType: 'Budget',
                    createdAt: '2019-01-06T01:24:22.678Z',
                    updatedAt: '2019-09-05T01:00:12.989Z'
                  }
                ]
              }
            when 'file-package'
              # use example from forge
              {
                hub_id: input['hub_id'],
                project_id: input['project_id'],
                results: [
                  {
                    id: 'a2e16076-d5bb-44b3-b451-fb1fb390e4fc',
                    recipient: 'GF8XKPKWM38E',
                    urn: 'urn:adsk.wipprod:fs.file:vf.PMbRnoPZR2mKDhau2uw4SQ?version=1',
                    errorInfo: {
                      code: 'missingTemplate',
                      message: 'Could not generate the document because the template is invalid.',
                      detail: 'Got timeout for POST upload URL.'
                    },
                    items: [
                      {
                        id: 'a2e16076-d5bb-44b3-b451-fb1fb390e4fc',
                        urn: 'urn:adsk.wipprod:fs.file:vf.PMbRnoPZR2mKDhau2uw4SQ?version=1',
                        name: 'GC_001.John-Smith.docx',
                        type: 'Document',
                        createdAt: '2019-01-06T01:24:22.678Z',
                        updatedAt: '2019-09-05T01:00:12.989Z'
                      }
                    ],
                    createdAt: '2019-01-06T01:24:22.678Z',
                    updatedAt: '2019-09-05T01:00:12.989Z'
                  }
                ]
              }
            when 'change-order'
              results = get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/#{input['change_order_type']}?limit=1")&.
                        dig('results')

              {
                hub_id: input['hub_id'],
                project_id: input['project_id'],
                results: results
              }
            when 'payment'
              results = get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/?filter[associationType]=#{input['payment_type']}&limit=1")&.
                        dig('results')
              {
                hub_id: input['hub_id'],
                project_id: input['project_id'],
                results: results
              }
            else
              results = get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}?limit=1")&.
                        dig('results')
              {
                hub_id: input['hub_id'],
                project_id: input['project_id'],
                results: results
              }
            end
          end
          # end case
        end,

        retry_on_response: [500, /error/],
        retry_on_request: ['GET'],
        max_retries: 3

    },

    upload_object: {
      title: 'Upload object to a project',
        description: lambda do |_connection, objects|
          "Upload <span class='provider'>#{objects['object']&.downcase || 'object'}</span> to a project in <span class='provider'>Autodesk Construction Cloud</span>"
        end,

        help: "Upload an object to a project.",

        config_fields: [
          {
            name: 'object',
            label: 'Object',
            optional: false,
            pick_list: 'upload_object_list',
            control_type: :select,
            hint: 'Select the object from picklist.'
          },
          {
            name: 'hub_id',
            label: 'Account name',
            control_type: 'select',
            pick_list: 'hub_list',
            optional: false,
            toggle_hint: 'Select account',
            toggle_field: {
              name: 'hub_id',
              label: 'Account ID',
              type: 'string',
              change_on_blur: true,
              control_type: 'text',
              toggle_hint: 'Enter account ID'
            }
          },
          {
            name: 'project_id',
            label: 'Project name',
            control_type: 'select',
            pick_list: 'project_list',
            pick_list_params: { hub_id: 'hub_id' },
            optional: false,
            toggle_hint: 'Select project',
            toggle_field: {
              name: 'project_id',
              label: 'Project ID',
              change_on_blur: true,
              type: 'string',
              control_type: 'text',
              toggle_hint: 'Enter project ID'
            }
          }
        ],

        input_fields: lambda do |object_definitions|
          object_definitions['upload_object_input']
        end,

        execute: lambda do |_connection, input|
          hub_id = input.delete('hub_id')
          project_id = input.delete('project_id')
          item_id = input.delete('item_id')

          case input['object']
          # start `upload document`
          when 'item'
            storage = {
              'jsonapi' => {
                'version' => '1.0'
              },
              'data' => {
                'type'=> 'objects',
                'attributes'=> {
                  'name'=> input['name']
                },
                'relationships' => {
                  'target' => {
                    'data' => {
                      'type' => 'folders',
                      'id' => input['folder_id']
                    }
                  }
                }
              }
            }

            # 1 create storage location
            response_storage = post("/data/v1/projects/#{project_id}/storage").
                        payload(storage).
                        after_error_response(/.*/) do |_code, body, _header, message|
                          error("#{message}: #{body}")
                        end

            object_id = response_storage&.dig('data', 'id')
            bucket_key = object_id.split('/').first.split('object:').last
            object_name = object_id.split('/').last

            #1b get signed url
            signedUrl = get("/oss/v2/buckets/#{bucket_key}/objects/#{object_name}/signeds3upload")

            #2 Upload file to storage location
            completeUpload = put(signedUrl['urls'].first).
                       request_body(input['file_content']).
                       headers('Content-Type' => 'application/octet-stream').
                       after_error_response(/.*/) do |_code, body, _header, message|
                         error("#{message}: #{body}")
                       end.

                       after_response do ||
                        post("/oss/v2/buckets/#{bucket_key}/objects/#{object_name}/signeds3upload").
                          payload(
                            {
                              "uploadKey": signedUrl['uploadKey']
                            }
                          ).
                         headers('Content-Type' => 'application/json').
                         after_error_response(/.*/) do |_code, body, _header, message|
                           error("#{message}: #{body}")
                         end
                       end

            if item_id.present?
              payload = {
                'jsonapi' => {
                  'version' => '1.0'
                },
                'data' => {
                  'type' => 'versions',
                  'attributes' => {
                    'name' => input['name'],
                    'extension' => {
                      'type' => 'versions:autodesk.bim360:File', 'version' => '1.0'
                    }
                  },
                  'relationships' => {
                    'item' => {
                      'data' => {
                        'type' => 'items',
                        'id' => item_id
                      }
                    },
                    'storage' => {
                      'data' => {
                        'type' => 'objects',
                        'id' => completeUpload['objectId']
                      }
                    }
                  }
                }
              }

              post("/data/v1/projects/#{project_id}/versions").
                            payload(payload).
                            after_error_response(/.*/) do |_code, body, _header, message|
                              error("#{message}: #{body}")
                            end&.dig('included', 0)&.merge({ hub_id: hub_id, project_id: project_id })

            else
              payload = {
                'jsonapi' => { 'version': '1.0' },
                'data' => {
                  'type' => 'items',
                  'attributes' => {
                    'displayName' => input['name'],
                    'extension' => {
                      'type' => 'items:autodesk.bim360:File',
                      'version' => '1.0'
                    }
                  },
                  'relationships' => {
                    'tip' => {
                      'data' => { 'type' => 'versions', 'id' => '1' }
                    },
                    'parent' => {
                      'data' => { 'type' => 'folders', 'id' => input['folder_id'] }
                    }
                  }
                },
                'included' => [
                  {
                    'type' => 'versions',
                    'id' => '1',
                    'attributes' => {
                      'name' => input['name'],
                      'extension' => {
                        'type': 'versions:autodesk.bim360:File',
                        'version': '1.0'
                      }
                    },
                    'relationships' => {
                      'storage' => {
                        'data' => { 'type' => 'objects', 'id' => completeUpload['objectId'] }
                      }
                    }
                  }
                ]
              }

              post("/data/v1/projects/#{project_id}/items").
                          payload(payload).
                          after_error_response(/.*/) do |_code, body, _header, message|
                            error("#{message}: #{body}")
                          end&.dig('included', 0)&.merge({ hub_id: hub_id, project_id: project_id })
            end
          #end `upload document`

          end

        end,

        output_fields: lambda do |object_definitions|
          [
            { name: 'hub_id', label: 'Account ID' },
            { name: 'project_id' }
          ]
          .concat(object_definitions['object_output_response'])
        end,

        sample_output: lambda do |_connection, input|
          case input['object']
          when 'item'
            folder_id = get("project/v1/hubs/#{input['hub_id']}/projects/#{input['project_id']}/topFolders?filter[type]=folders")&.dig('data', 0, 'id') || {}
            folder_id.present? ? get("/data/v1/projects/#{input['project_id']}/folders/#{folder_id}/search?page[limit]=1")&.dig('included', 0)&.merge(hub_id: input['hub_id'], project_id: input['project_id']) : {}
          end
        end

    }
  },

  triggers: {
    new_updated_object_in_project: {
      title: "New or updated object in a project",

      description: lambda do |_connection, objects|
        "New or updated <span class='provider'>#{objects['object']&.downcase ||'object'}</span> in a project in <span class='provider'>Autodesk Construction Cloud</span>"
      end,

      help: "Triggers when an object is created or updated in a project.",

      config_fields: [
        {
          name: 'object',
          optional: false,
          pick_list: 'new_updated_object_list',
          control_type: 'select',
          hint: 'Select the object from picklist.',
          extends_schema: true
        },
        {
          name: 'hub_id',
          label: 'Account name',
          control_type: 'select',
          pick_list: 'hub_list',
          optional: false
        },
        {
          name: 'project_id',
          label: 'Project name',
          control_type: 'select',
          pick_list: 'project_list',
          pick_list_params: { hub_id: 'hub_id' },
          optional: false
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['new_updated_object_input'].concat(
          [
            {
              name: 'since',
              label: 'When first started, this recipe should pick up events from',
              hint: 'When you start recipe for the first time, it picks up trigger events from this specified date and time. ' \
              'Leave empty to get records created or updated one hour ago',
              sticky: true,
              type: 'timestamp'
            }
          ]
        )
      end,

      poll: lambda do |_connection, input, closure|
          closure ||= {}
          updated_after = closure['updated_after'] || (input['since'] || 1.hour.ago).to_time.utc.iso8601

          hub_id = closure&.[]('hub_id') || input['hub_id']
          project_id = closure&.[]('project_id') || input['project_id']
          folder_id = closure&.[]('folder_id') || input['folder_id']
          include_subfolders = closure&.[]('include_subfolders') || input['subfolders']

          response = if closure['next_page_url'].present?
                       get(closure['next_page_url'])
                     else

                       case input['object']
                       when 'item'
                        if include_subfolders == 'yes'
                          get("/data/v1/projects/#{project_id}/folders/#{folder_id}/search?filter[lastModifiedTime]-ge=#{updated_after}")
                        else
                          get("/data/v1/projects/#{project_id}/folders/#{folder_id}/contents?filter[lastModifiedTimeRollup]-ge=#{updated_after}&filter[type]=items&page[limit]=10")
                        end

                      when 'cost'
                        project_id = project_id.split('.').last

                        case input['cost_object']
                        when 'change-order'
                          get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/#{input['change_order_type']}?filter[lastModifiedSince]=#{updated_after}&limit=10")
                        when 'expense'
                          get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}?filter[lastModifiedSince]=#{updated_after}&limit=10&include=expenseItems,mainContract,attributes")
                        else
                          get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}?filter[lastModifiedSince]=#{updated_after}&limit=10&include=attributes")
                        end

                       when 'takeoff'
                         project_id = input['project_id'].split('.').last

                         case input['takeoff_object']
                         when 'takeoff_package'
                          get("/construction/takeoff/v1/projects/#{project_id}/packages?limit=50")
                         end

                       when 'form'
                         project_id = input['project_id'].split('.').last
                         get("/construction/forms/v1/projects/#{project_id}/forms?limit=50&updatedAfter=#{updated_after}", input.except(:project_id, :hub_id, :object, :since).compact)

                       when 'issue'
                         project_id = input['project_id'].split('.').last
                         get("/construction/issues/v1/projects/#{project_id}/issues?limit=10&filter[updatedAt]=#{updated_after}...#{now.utc.iso8601}&sortBy=updatedAt")
                       end

                    end

          # prep the data for output
          case input['object']

          # prep 'documents' records
          when 'item'
            if include_subfolders == 'yes'
              items = response['data']
            else
              items = response['data']
            end

            records = items&.map do |out|
              out.merge(project_id: project_id, hub_id: hub_id)
            end&.sort_by { |res| res.dig('attributes', 'lastModifiedTime') }

            if records.present? && records.length > 0 && (next_page_url = response.dig('links', 'next', 'href')).present?
              # closure['next_page_url'] = next_page_url
              closure = {
                'next_page_url' => next_page_url
              }
            else
              #closure['next_page_url'] = nil
              #closure['updated_after'] = records.present? ? Array.wrap(records.last.dig('attributes', 'lastModifiedTime')) : now.to_time.utc.strftime('%Y-%m-%dT%H:%M:%S')
              closure = {
                'hub_id': hub_id,
                'project_id': project_id,
                'folder_id': folder_id,
                'include_subfolders': include_subfolders,
                'updated_after': now.to_time.utc.iso8601
              }
            end


          # prep 'cost' records
          when 'cost'
            items = response.dig('results')
            records = items&.map do |out|
              out.merge(project_id: project_id, hub_id: hub_id)
            end&.sort_by { |res| res.dig('updatedAt') }
        
            puts records
            if records.present? && records.length > 0 && (next_page_url = response.dig('pagination', 'nextUrl')).present?
              closure = {
                'next_page_url' => next_page_url.gsub('/api/','/cost/')
              }
              #closure['next_page_url'] = next_page_url
            else
              closure = {
                'hub_id': hub_id,
                'project_id': project_id,
                'updated_after': now.to_time.utc.iso8601
              }
            end

          when 'form'
            items = response.dig('data')
            records = items&.map do |out|
                if out['updatedAt'].present? && out['updatedAt'].to_time.to_i > updated_after.to_time.to_i
                  out.merge(project_id: input['project_id'], hub_id: input['hub_id'])
                else
                  nil
                end
            end.compact.sort_by { |res| res.dig('updatedAt') }

            if (next_page_url = response.dig('pagination', 'nextUrl')).present?
              closure['next_page_url'] = next_page_url
            else
              closure['next_page_url'] = nil
              closure['updated_after'] = now.to_time.utc.iso8601
            end

          when 'issue'
            items = response.dig('results')
            records = items&.map do |out|
                if out['updatedAt'].present? && out['updatedAt'].to_time.to_i > updated_after.to_time.to_i
                  out.merge(project_id: input['project_id'], hub_id: input['hub_id'])
                else
                  nil
                end
            end.compact.sort_by { |res| res.dig('updatedAt') }

            if (next_page_url = response.dig('pagination', 'next')).present?
              if next_page_url.include?('https://developer.api.autodesk.com')
                closure['next_page_url'] = next_page_url
              else
                closure['next_page_url'] = 'https://developer.api.autodesk.com/construction/issues/v1/' + next_page_url
              end
            else
              closure['next_page_url'] = nil
              closure['updated_after'] = now.to_time.utc.iso8601
            end

          # prep 'takeoff' records
          when 'takeoff'
            items = response.dig('results')
            records = items&.map do |out|
                if out['updatedAt'].present? && out['updatedAt'].to_time.to_i > updated_after.to_time.to_i
                  out.merge(project_id: input['project_id'], hub_id: input['hub_id'])
                else
                  nil
                end
            end.compact.sort_by { |res| res.dig('updatedAt') }

            if (next_page_url = response.dig('pagination', 'nextUrl')).present?
              closure['next_page_url'] = next_page_url
            else
              closure['next_page_url'] = nil
              closure['updated_after'] = now.to_time.utc.iso8601
            end
          # end data prep for output
          end

          {
            events: records || [],
            next_poll: closure,
            # can_poll_more: response.dig('links', 'next', 'href').present?
            can_poll_more: closure['next_page_url'].present?
          }

      end,

      dedup: lambda do |record|
        "#{record['id']}@#{record.dig('lastModifiedTime')||record.dig('updatedAt')}"
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: 'hub_id', label: 'Account ID' },
          { name: 'project_id' }
        ].concat(object_definitions['object_output_response'])
      end,

      sample_output: lambda do |_connection, input|
        # start case
        case input['object']
        when 'item'
          get("/data/v1/projects/#{input['project_id']}/folders/#{input['folder_id']}/search?page[limit]=1")&.
          dig('included', 0)&.
          merge(hub_id: input['hub_id'], project_id: input['project_id'])
        when 'cost'
          project_id = input['project_id'].split('.').last

          case input['cost_object']
          when 'change-order'
            get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/#{input['change_order_type']}?limit=1")&.
            dig('results', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          when 'payment'
            get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}/?filter[associationType]=#{input['payment_type']}&limit=1")&.
            dig('results', 0)&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          else
            get("/cost/v1/containers/#{project_id}/#{input['cost_object'].pluralize}?limit=1")&.
            dig('results')[0]&.
            merge(hub_id: input['hub_id'], project_id: input['project_id'])
          end
        end
        # end case
      end
    },

    new_event_in_project: {
      title: "New event in a project",

      description: lambda do |_connection, objects|
        "<span class='provider'>#{objects['object']||'New event'}</span> in a project in <span class='provider'>Autodesk Construction Cloud</span>"
      end,

      help: "Triggers when an event occurs in a project.",

      config_fields: [
        {
          name: 'object',
          label: 'Event',
          optional: false,
          pick_list: 'new_event_list',
          control_type: 'select',
          hint: 'Select the event from picklist.',
          extends_schema: true
        },
        {
          name: 'hub_id',
          label: 'Account name',
          control_type: 'select',
          pick_list: 'hub_list',
          optional: false
        },
        {
          name: 'project_id',
          label: 'Project name',
          control_type: 'select',
          pick_list: 'project_list_all',
          pick_list_params: { hub_id: 'hub_id' },
          optional: false
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['new_event_input'].concat(
          [

          ]
        )
      end,

      webhook_subscribe: lambda do |webhook_url, connection, input, recipe_id|
        hookAttributes = {}
        if input['hookAttribute'].present? && input['hookAttribute'].length > 0
          input['hookAttribute'].each do |i|
            key = i['key']
            value = i['value']
            hookAttributes[key] = value
          end
        end

        region = get("/project/v1/hubs/#{input['hub_id']}").dig('data','attributes','region')
        payload = {
          'callbackUrl' => webhook_url,
          'scope' => {
            'folder' => input['folder_id']
          },
          'filter' => input['filter'],
          'hubId' => input['hub_id'],
          'projectId' => input['project_id'],
          'hookAttribute' => hookAttributes
        }

        post("/webhooks/v1/systems/data/events/#{input['object']}/hooks").
          payload(payload).
          headers({ 'x-ads-region': region }).
          after_response do |code, body, headers|
            { 'unsubscribe': headers['location'] }
          end.
          after_error_response do |code, body, headers|
            { 'message': body }
          end
      end,

      webhook_notification: lambda do |input, payload, extended_input_schema, extended_output_schema, headers, params|
        fullPath = payload.dig('payload','ancestors').slice(2,99999).pluck('name').join('/')
        payload&.merge({ context: { fullPath: fullPath } })
      end,

      webhook_unsubscribe: lambda do |webhook_subscribe_output|
        delete(webhook_subscribe_output['unsubscribe'])
      end,

      dedup: lambda do |record|
        record
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['object_output_response'].concat(
          [
            { name: 'context', type: 'object', properties:
              [
                { name: 'fullPath' }
              ]
            }
          ]
        )
      end,

      sample_output: lambda do |_connection, input|

      end
    }
  },

  pick_lists: {
    new_updated_object_list: lambda do |_connection|
      [
        ['Cost object', 'cost'],
        ['Document', 'item'],
        ['Form', 'form'],
        ['Issue', 'issue'],
        ['Takeoff object', 'takeoff']
      ]
    end,

    new_event_list: lambda do |_connection|
      [
        [ 'New or updated document', 'dm.version.added' ],
        [ 'New or updated document attribute', 'dm.version.modified' ],
        [ 'Deleted document', 'dm.lineage.updated' ],
        [ 'New folder', 'dm.folder.added' ],
        [ 'Updated folder', 'dm.folder.modified' ],
        [ 'Moved folder', 'dm.folder.moved' ],
      ]
    end,

    new_updated_cost_list: lambda do |_connection|
      [
        ['Budget', 'budget'],
        ['Change order', 'change-order'],
        ['Contract', 'contract'],
        ['Cost item', 'cost-item'],
        ['Expense', 'expense'],
        ['Main contract', 'main-contract'],
        ['Payment application', 'payment']
      ]
    end,

    new_takeoff_list: lambda do |_connection|
      [
        ['Takeoff package', 'takeoff_package']
      ]
    end,

    create_object_list: lambda do |_connection|
      [
        ['Cost object', 'cost'],
        ['Folder', 'folder'],
        ['Issue', 'issue'],
        ['RFI', 'rfi'],
        ['RFI comment', 'rfi_comment'],
        ['Webhook', 'webhook']
      ]
    end,

    create_cost_list: lambda do |_connection|
      [
        ['Attachment', 'attachment'],
        ['Budget', 'budget'],
        ['Change order', 'change-order'],
        ['Contract', 'contract'],
        ['Cost item', 'cost-item'],
        ['Expense', 'expense'],
        ['Main contract', 'main-contract'],
        ['Time sheet', 'time-sheet']
      ]
    end,

    download_object_list: lambda do |_connection|
      [
        ['Document', 'item']
      ]
    end,

    get_object_list: lambda do |_connection|
      [
        ['Cost object', 'cost'],
        ['Document', 'item'],
        ['Folder', 'folder'],
        ['Form', 'form'],
        ['Issue', 'issue'],
        ['Project', 'project'],
        ['RFI', 'rfi'],
        ['Takeoff Object', 'takeoff'],
        ['User', 'user']
      ]
    end,

    get_cost_list: lambda do |_connection|
      [
        ['Budget', 'budget'],
        ['Change order', 'change-order'],
        ['Contract', 'contract'],
        ['Cost item', 'cost-item'],
        ['Expense', 'expense'],
        ['Main contract', 'main-contract'],
        ['Payment application', 'payment'],
        ['Time sheet', 'time-sheet'],
        ['Tracking item instance', 'performance-tracking-item-instance']
      ]
    end,

    get_takeoff_list: lambda do |_connection|
      [
        ['Takeoff Package', 'takeoff_package'],
        ['Takeoff Type', 'takeoff_type'],
        ['Takeoff Item', 'takeoff_item']
      ]
    end,

    update_object_list: lambda do |_connection|
      [
        ['Cost object', 'cost'],
        ['Document', 'item'],
        ['Folder', 'folder'],
        ['Issue', 'issue'],
        ['RFI', 'rfi']
      ]
    end,

    update_cost_list: lambda do |_connection|
      [
        ['Budget', 'budget'],
        ['Change order', 'change-order'],
        ['Contract', 'contract'],
        ['Cost item', 'cost-item'],
        ['Expense', 'expense'],
        ['Main contract', 'main-contract'],
        ['Time sheet', 'time-sheet']
      ]
    end,

    search_object_list: lambda do |_connection|
      [
        ['Cost object', 'cost'],
        ['Document', 'item'],
        ['Form', 'form'],
        ['Issue', 'issue'],
        ['RFI', 'rfi'],
        ['RFI comment', 'rfi_comment'],
        ['RFI reference', 'rfi_reference'],
        ['Takeoff object', 'takeoff']
      ]
    end,

    search_cost_list: lambda do |_connection|
      [
        ['Attachments', 'attachment'],
        ['Budgets', 'budget'],
        ['Change orders', 'change-order'],
        ['Contracts', 'contract'],
        ['Cost items', 'cost-item'],
        ['Documents', 'document'],
        ['Expenses', 'expense'],
        ['File packages', 'file-package'],
        ['Main contracts', 'main-contract'],
        ['Payment applications', 'payment'],
        ['Time sheet', 'time-sheet'],
        ['Tracking item instance', 'performance-tracking-item-instance']
      ]
    end,

    search_takeoff_list: lambda do |_connection|
      [
        ['Takeoff items', 'takeoff_item'],
        ['Takeoff packages', 'takeoff_package'],
        ['Takeoff types', 'takeoff_type'],
        ['Classifications', 'classification'],
        ['Classification systems', 'classification_system']
      ]
    end,

    upload_object_list: lambda do |_connection|
      [
        ['Document', 'item']
      ]
    end,

    association_type_list: lambda do |_connection|
      [
        ['Budget', 'Budget'],
        ['Budget payment', 'BudgetPayment'],
        ['Change order', 'FormInstance'],
        ['Contract', 'Contract'],
        ['Cost item', 'CostItem'],
        ['Cost payment', 'Payment'],
        ['Expense', 'Expense'],
        ['Main contract', 'MainContract']
      ]
    end,

    change_order_list: lambda do |_connection|
      [
        ['PCO', 'pco'],
        ['RFQ', 'rfq'],
        ['RCO', 'rco'],
        ['OCO', 'oco'],
        ['SCO', 'sco']
      ]
    end,

    hub_list: lambda do |_connection|
      hubs = get('/project/v1/hubs')['data']
      hubs&.sort_by { |hub| [hub.dig('attributes', 'name')] }&.
      map do |hub|
        [hub.dig('attributes', 'name'), hub['id']]
      end
    end,

    project_list: lambda do |_connection, hub_id:|
      if hub_id.present? && hub_id.slice(0,1) != '#'
        projects = get("project/v1/hubs/#{hub_id}/projects")['data']
        #projects = projects.select { |project| project.dig('attributes', 'extension', 'data', 'projectType') === 'ACC' }
        projects&.sort_by { |project| [project.dig('attributes', 'name')] }&.
        map do |project|
          [project.dig('attributes','name'), project['id']]
        end
      end
    end,

    project_list_all: lambda do |_connection, hub_id:|
      if hub_id.present? && hub_id.slice(0,1) != '#'
        projects = get("project/v1/hubs/#{hub_id}/projects")['data']
        projects&.sort_by { |project| [project.dig('attributes', 'name')] }&.
        map do |project|
          [project.dig('attributes','name'), project['id']]
        end
      end
    end,

    folders_list: lambda do |_connection, **args|
      if args[:project_id].present? && args[:project_id].length == 38
        if (parent_id = args&.[](:__parent_id)).present?
          get("/data/v1/projects/#{args[:project_id]}/folders/#{parent_id}/contents?filter[type]=folders")['data']&.
            sort_by { |folder| [folder.dig('attributes', 'displayName')] }&.
            map do |folder|
              [folder.dig('attributes', 'displayName'), folder['id'], nil, true]
            end
        else
          get("project/v1/hubs/#{args[:hub_id]}/projects/#{args[:project_id]}/topFolders?filter[type]=folders")['data']&.
            map do |folder|
              [folder.dig('attributes', 'displayName'), folder['id'], nil, true]
            end || []
        end
      end
    end,

    folder_items: lambda do |_connection, project_id:, folder_id:|
      if project_id.length == 38 && folder_id.present?
        get("/data/v1/projects/#{project_id}/folders/#{folder_id}/contents?filter[type]=items")['data']&.
        map do |item|
          [item.dig('attributes', 'displayName'), item['id']]
        end
      end
    end,

    form_templates: lambda do |_connection, project_id:|
      if project_id.present?
        get("/construction/forms/v1/projects/#{project_id.split('.').last}/form-templates?sortOrder=asc")['data']&.
        map do |form|
          [form['name'], form['id']]
        end
      end
    end,

    search_issue_type: lambda do |_connection, project_id:|
      if project_id.present? && !project_id.include?('#')
        get("/construction/issues/v1/projects/#{project_id.split('.').last}/issue-types")['results']&.
        map do |issue|
          [issue['title'], issue['id']]
        end
      end
    end,

    search_issue_sub_type: lambda do |_connection, project_id:, issue_type_id:|
      if project_id.present? && issue_type_id.present? && !project_id.include?('#')
        issue_type = get("/construction/issues/v1/projects/#{project_id.split('.').last}/issue-types?include=subtypes")['results']&.select { |issue| issue['id'] == issue_type_id }.first
        issue_type['subtypes']&.map do |subtype|
          [subtype['title'], subtype['id']]
        end
      end
    end
  }
}