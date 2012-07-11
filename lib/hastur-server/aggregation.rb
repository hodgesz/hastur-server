require "hastur-server/aggregation/simple"
require "hastur-server/aggregation/merge"
require "hastur-server/aggregation/lookup"
require "hastur-server/aggregation/compound"
require "hastur-server/aggregation/formats"

module Hastur
  module Aggregation
    class InvalidAggFunError < StandardError ; end
    class InvalidAggSyntaxError < StandardError ; end
    extend self

    # series = { uuid => { name => { timestamp => value, ... } } }
    def evaluate(string, series)
      exp = tokenize(string)

      until exp.none?
        args = []
        until args[-1].kind_of? Symbol or exp.none?
          args.push exp.pop
        end

        fun = args.pop
        if fun.kind_of? Symbol
          series = self.send fun, series, *args
        else
          raise InvalidAggFunError.new fun.inspect
        end
      end
      series
    end

    #
    # Tokenize an aggregation expression.
    #
    # @param [String] string aggregation expression in a string
    # @return [Array<String,Symbol,Fixnum,Float>] tokens
    #
    def tokenize(string)
      parts = string.split(/\s*[\(\)]\s*/).map do |token|
        token.split(/\s*,\s*/).map do |exp|
          if @functions.has_key? exp
            @functions[exp]
          elsif exp =~ /\A[\-\+]?\d+\Z/
            exp.to_i
          elsif exp =~ /\A[\-\+]?\d*\.\d+\Z/
            exp.to_f
          elsif exp =~ /\A\w+\Z/
            exp
          else
            raise InvalidAggSyntaxError.new exp.inspect
          end
        end
      end
      parts.flatten
    end
  end
end
