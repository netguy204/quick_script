require 'ostruct'

module QuickScript
	module Interaction

		## HELPER ACTIONS
		
		def layout_only
			render :text => '', :layout => 'application'
		end

		protected

		class << self
			def included(base)
				base.send :before_filter, :handle_params if base.respond_to? :before_filter
			end
		end

		class ScopeResponder
			def initialize
				@names = {}
			end
			def criteria(scope)
				crit = nil

				if @names['before_filter']
					crit = @names['before_filter'].call
				end

				scope.selectors.each do |k, v|
					if crit.nil?
						crit = @names[k].call(*v)
					else
						crit.merge!(@names[k].call(*v))
					end
				end
				return crit
			end

			def items(scope)
				crit = criteria(scope)
				if crit.respond_to? :limit
					items = crit.limit(scope.limit).offset(scope.offset).to_a
				else
					items = crit[scope.offset..(scope.offset + scope.limit)]
				end
				return items
			end

			def count(scope)
				crit = criteria(scope)
				crit.count
			end
			def method_missing(method_sym, *args, &block)
				@names[method_sym.to_s] = block
			end
		end

		def json_resp(data, meta=true, opts = {})
			meta = 200 if meta == true 
			meta = 404 if meta == false 
			opts[:data] = data
			opts[:meta] = meta
			opts[:success] = meta == 200

			if meta != 200 && opts[:error].blank?
				opts[:error] = "An error occurred"
			end
			opts.to_json
		end

		def json_error(errors, meta = 404, opts = {})
			json_resp({:errors => errors}, meta, {error: errors[0]})
		end

		def render_data(data, meta=true, opts={})
			render :json => json_resp(data, meta, opts)
		end

		def render_error(err)
			render :json => json_error([err])
		end

		def render_result(result, &block)

			resp = OpenStruct.new
			resp.success = result[:success]
			resp.meta = result[:meta] || (result[:success] ? 200 : 400)
      if !((data = result[:data]).nil?)
        if data.respond_to?(:to_api)
          resp.data = data.to_api
        else
          resp.data = data
        end
      end
			resp.error = result[:error]

			block.call(resp) unless block.nil?

			resp_h = resp.marshal_dump

			render :json => resp_h.to_json, :status => resp.meta
		end

		def handle_params
			# handle scope
			@scope = {}
			class << @scope
				def selectors; return self[:selectors]; end
				def args; return self[:args]; end
				def limit; return self[:limit] || 100; end
				def page; return self[:page] || 1; end
				def offset; return self[:offset] || 0; end
			end
			if params[:scope]
				if params[:scope].is_a? Array
					@scope[:selectors] = {params[:scope].first => params[:scope][1..-1]}
					@scope[:args] = params[:scope][1..-1]
				else
					# json selectors
					@scope[:selectors] = JSON.parse(params[:scope])
				end
			end
			@scope[:limit] = params[:limit].to_i if params[:limit]
			@scope[:page] = params[:page].to_i if params[:page]
			@scope[:offset] = (@scope[:page] - 1) * @scope[:limit] if params[:page] && params[:limit]

			# handle api_ver
			@api_version = request.headers['API-Version'] || 0
			ENV['API_VER'] = @api_version.to_s
		end

		def get_scoped_items(model, scope, limit, offset)
				@items = model
				scope.each do |m, args|
					# validate scope
					next unless can? m.to_sym, model
					args = [current_user.id.to_s] if m.include?("my_") && current_user
					if args == []
						@items = @items.send(m)
					else
						@items = @items.send(m, *args)
					end
				end
				return [] if @items == model
				@items = @items.limit(limit).offset(offset)
		end

		def respond_to_scope(resp_action=:items, responder=nil, &block)
			responder ||= ScopeResponder.new
			block.call(responder) if block
			responder.send(resp_action, @scope)
		end

	end
end
