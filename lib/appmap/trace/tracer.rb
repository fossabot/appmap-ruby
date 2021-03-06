module AppMap
  module Trace
    MethodEventStruct =
      Struct.new(:id, :event, :defined_class, :method_id, :path, :lineno, :static, :thread_id)

    class Tracers
      def initialize
        @tracers = []
      end

      def empty?
        @tracers.empty?
      end

      def trace(functions, enable: true)
        AppMap::Trace::Tracer.new(functions).tap do |tracer|
          @tracers << tracer
          tracer.enable if enable
        end
      end

      def record_event(event)
        @tracers.each do |tracer|
          tracer.record_event(event)
        end
      end

      def delete(tracer)
        return unless @tracers.member?(tracer)

        @tracers.delete(tracer)
        tracer.disable
      end
    end

    class << self
      def tracers
        @tracers ||= Tracers.new
      end
    end

    # @appmap
    class MethodEvent < MethodEventStruct
      LIMIT = 100

      COUNTER_LOCK = Mutex.new # :nodoc:
      @@id_counter = 0

      class << self
        # Build a new instance from a TracePoint.
        def build_from_tracepoint(me, tp, path)
          me.id = next_id
          me.event = tp.event

          if tp.defined_class.singleton_class?
            me.defined_class = (tp.self.is_a?(Class) || tp.self.is_a?(Module)) ? tp.self.name : tp.self.class.name
          else
            me.defined_class = tp.defined_class.name
          end

          me.method_id = tp.method_id
          me.path = path
          me.lineno = tp.lineno
          me.static = tp.defined_class.name.nil?
          me.thread_id = Thread.current.object_id
        end

        # Gets the next serial id.
        #
        # This method is thread-safe.
        # @appmap
        def next_id
          COUNTER_LOCK.synchronize do
            @@id_counter += 1
          end
        end

        # Gets a value, by key, from the trace point binding.
        # If the method raises an error, it can be handled by the optional block.
        def value_in_binding(tp, key, &block)
          tp.binding.eval(key.to_s)
        rescue NameError, ArgumentError
          yield if block_given?
        end

        # Gets a display string for a value. This is not meant to be a machine deserializable value.
        def display_string(value)
          return nil unless value

          last_resort_string = lambda do
            warn "AppMap encountered an error inspecting a #{value.class.name}: #{$!.message}"
            '*Error inspecting variable*'
          end

          value_string = \
            begin
              value.to_s
            rescue NoMethodError
              begin
                value.inspect
              rescue StandardError
                last_resort_string.call
              end
            rescue StandardError
              last_resort_string.call
            end

          value_string[0...LIMIT].encode('utf-8', invalid: :replace, undef: :replace, replace: '_')
        end
      end

      alias static? static
    end

    # @appmap
    class MethodCall < MethodEvent
      attr_accessor :parameters, :receiver

      class << self
        # @appmap
        def build_from_tracepoint(mc = MethodCall.new, tp, path)
          mc.tap do |_|
            mc.parameters = collect_parameters(tp)
            mc.receiver = collect_self(tp)
            MethodEvent.build_from_tracepoint(mc, tp, path)
          end
        end

        def collect_self(tp)
          {
            class: tp.self.class.name,
            object_id: tp.self.__id__,
            value: display_string(tp.self)
          }
        end

        def collect_parameters(tp)
          -> { tp.self.method(tp.method_id).parameters rescue [] }.call.collect do |pinfo|
            kind, key = pinfo
            value = value_in_binding(tp, key)
            {
              name: key,
              class: value.class.name,
              object_id: value.__id__,
              value: display_string(value),
              kind: kind # :req, :rest, :key, :keyrest, :block
            }
          end
        end
      end

      def to_h
        super.tap do |h|
          h[:parameters] = parameters
          h[:receiver] = receiver
        end
      end
    end

    class MethodReturnIgnoreValue < MethodEvent
      attr_accessor :parent_id, :elapsed

      class << self
        def build_from_tracepoint(mr = MethodReturnIgnoreValue.new, tp, path, parent_id, elapsed)
          mr.tap do |_|
            mr.parent_id = parent_id
            mr.elapsed = elapsed
            MethodEvent.build_from_tracepoint(mr, tp, path)
          end
        end
      end

      def to_h
        super.tap do |h|
          h[:parent_id] = parent_id
          h[:elapsed] = elapsed
        end
      end
    end

    class MethodReturn < MethodReturnIgnoreValue
      attr_accessor :return_value

      class << self
        def build_from_tracepoint(mr = MethodReturn.new, tp, path, parent_id, elapsed)
          mr.tap do |_|
            mr.return_value = {
              class: tp.return_value.class.name,
              value: display_string(tp.return_value),
              object_id: tp.return_value.__id__
            }
            MethodReturnIgnoreValue.build_from_tracepoint(mr, tp, path, parent_id, elapsed)
          end
        end
      end

      def to_h
        super.tap do |h|
          h[:return_value] = return_value
        end
      end
    end

    # Processes a series of calls into recorded events.
    # Each call to the handle should provide a TracePoint (or duck-typed object) as the argument.
    # On each call, a MethodEvent is constructed according to the nature of the TracePoint, and then
    # stored using the record_event method.
    # @appmap
    class TracePointHandler
      attr_accessor :call_constructor, :return_constructor

      DEFAULT_HANDLER_CLASSES = {
        call: MethodCall,
        return: MethodReturn
      }.freeze

      # @appmap
      def initialize(tracer)
        @pwd = Dir.pwd
        @tracer = tracer
        @call_stack = Hash.new { |h, k| h[k] = [] }
        @handler_classes = {}
      end

      # @appmap
      def handle(tp)
        # Absoute paths which are within the current working directory are normalized
        # to be relative paths.
        path = tp.path
        if path.index(@pwd) == 0
          path = path[@pwd.length+1..-1]
        end

        method_event = \
          if tp.event == :call && (function = @tracer.lookup_function(path, tp.lineno))
            call_constructor = handler_class(function, tp.event)
            call_constructor.build_from_tracepoint(tp, path).tap do |c|
              @call_stack[Thread.current.object_id] << [ tp.defined_class, tp.method_id, c.id, Time.now, function ]
            end
          elsif (c = @call_stack[Thread.current.object_id].last) &&
                c[0] == tp.defined_class &&
                c[1] == tp.method_id
            function = c[4]
            @call_stack[Thread.current.object_id].pop
            return_constructor = handler_class(function, tp.event)
            return_constructor.build_from_tracepoint(tp, path, c[2], Time.now - c[3])
          end

        @tracer.record_event method_event if method_event

        method_event
      rescue
        puts $!.message
        puts $!.backtrace.join("\n")
        # XXX If this exception doesn't get reraised, internal errors
        # (e.g. a missing method on TracePoint) get silently
        # ignored. This allows tests to pass that should fail, which
        # is bad, but is it desirable otherwise?
        raise
      end

      protected

      # Figure out which handler class should be used for a trace event. It may be
      # a custom handler, e.g. in case we are processing a special named function such as a
      # web server entry point, or it may be the standard :call or :return handler.
      def handler_class(function, event)
        cache_key = [function.location, event]
        cached_handler = @handler_classes[cache_key]
        return cached_handler if cached_handler

        return default_handler_class(event) unless function.handler_id

        require "appmap/trace/event_handler/#{function.handler_id}"

        AppMap::Trace::EventHandler
          .const_get(function.handler_id.to_s.camelize)
          .const_get(event.to_s.capitalize).tap do |handler|
          @handler_classes[cache_key] = handler
        end
      end

      def default_handler_class(event)
        DEFAULT_HANDLER_CLASSES[event] or raise "No handler class for #{event.inspect}"
      end
    end

    # @appmap
    class Tracer
      # Trace a specified set of functions.
      #
      # functions Array of AppMap::Feature::Function.
      # @appmap
      def initialize(functions)
        @functions = functions

        @functions_by_location = functions.each_with_object({}) do |m, memo|
          path, lineno = m.location.split(':', 2)
          memo[path] ||= {}
          memo[path][lineno.to_i] = m
          memo
        end

        @events_mutex = Mutex.new
        @events = []
      end

      def enable
        handler = TracePointHandler.new(self)
        @trace_point = TracePoint.trace(:call, :return, &handler.method(:handle))
      end

      # Private function. Use AppMap.tracers#delete.
      def disable # :nodoc:
        @trace_point.disable
      end

      # Whether the indicated file path and lineno is a breakpoint on which
      # execution should interrupted.
      # @appmap
      def lookup_function(path, lineno)
        (methods_by_path = @functions_by_location[path]) && methods_by_path[lineno]
      end

      # Record a program execution event.
      #
      # The event should be one of the MethodEvent subclasses.
      #
      # This method is thread-safe.
      # @appmap
      def record_event(event)
        @events_mutex.synchronize do
          @events << event
        end
      end

      # Whether there is an event available for processing.
      #
      # This method is thread-safe.
      def event?
        @events_mutex.synchronize do
          !@events.empty?
        end
      end

      # Gets the next available event, if any.
      #
      # This method is thread-safe.
      def next_event
        @events_mutex.synchronize do
          @events.shift
        end
      end
    end
  end
end
