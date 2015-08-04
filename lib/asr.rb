require 'minitest'
require 'diffy'
require 'descendants_tracker'
require 'parser/current'

require 'pry'

module Minitest
  # Disable autorun from test files
  @@installed_at_exit = true
end

class SoftwareAutoRepair
  def initialize(code_path, suite_path)
    require code_path
    require suite_path

    @code, @suite = File.read(code_path), Minitest::Runnable.runnables.last

    parse_program
  end

  def try_to_fix
    return if failing_tests.none?

    each_variant do |variant|
      load_variant(variant)

      if run_failing_tests # Bug Oracle
        return print_fix(variant) if run_all_tests # Regression Oracle
      end
    end

    puts "No fixes found"
  end

  def run_test(test) # Returns true when test passes
    @suite.new(test).run.passed?
  end

  def run_all_tests
    @suite.runnable_methods.all? {|test| run_test(test) }
  end

  def run_failing_tests
    failing_tests.all? {|test| run_test(test) }
  end

  def failing_tests
    @failing_tests ||= @suite.runnable_methods.reject {|test| run_test(test) }
  end

  def each_variant
    each_alternatives_mapper {|mapper| yield rewrite_program_for(mapper) }
  end

private
  def rewrite_program_for(variant_mapper)
    buffer  = Parser::Source::Buffer.new('(alternative)').tap {|b| b.source = @code}
    rewriter = AlternativeProgramRewriter.new(variant_mapper)

    rewriter.rewrite(buffer, @program_template)
  end

  def print_fix(variant)
    puts "Generated fix for failing tests:\n"
    puts Diffy::Diff.new(@code, variant, context: 3, include_diff_info: true).to_s(:color).
      sub(%r{--- /tmp/diffy.[^\n]+}, '--- original file').
      sub(%r{\+\+\+ /tmp/diffy.[^\n]+}, '+++ fixed file')
  end

  def ast
    @ast ||= Parser::CurrentRuby.parse(@code)
  end

  def as_source(ast)
    Unparser.unparse(ast)
  end

  def load_variant(variant)
    old_verbose, $VERBOSE = $VERBOSE, nil
    TOPLEVEL_BINDING.eval(variant)
  ensure
    $VERBOSE = old_verbose
  end

  def parse_program
    detector = HotspotsDetector.new
    @program_template = detector.process(ast)
    @detected_hotspots = detector.detected_hotspots
  end

  def each_alternatives_mapper(&bl)
    first, *rest = @detected_hotspots.map(&:alternatives_mapper)
    rest.empty? ? first.each(&bl) : first.product(*rest) {|mappers| yield mappers.reduce(:merge) }
  end
end

class HotspotsDetector < Parser::AST::Processor
  def initialize
    @hotspots_stack = []
  end

  def detected_hotspots
    @hotspots_stack
  end

  def on_send(node)
    if hotspot_class = MessageHotspot.detect_hotspot_at(node)
      rec, sel, *args = *node

      lower_hotspots = collect_hotspots do
        rec = process(rec)
        args = process_all(args)
      end

      hotspot_at(hotspot_class, node, [rec, sel, *args], lower_hotspots)
    else
      super
    end
  end

  def on_block(node)
    if hotspot_class = BlockHotspot.detect_hotspot_at(node)
      exp, *rest = *node
      rec, sel, *args = *exp

      lower_hotspots = collect_hotspots do
        rec = process(rec)
        args = process_all(args)
        rest = process_all(rest)
      end

      exp = exp.updated(nil, [rec, sel, *args])
      hotspot_at(hotspot_class, node, [exp ,*rest], lower_hotspots)
    else
      super
    end
  end

private
  def hotspot_at(klass, node, new_childs, conflicts)
    new_node = node.updated(nil, new_childs)
    klass.new(new_node, conflicts: conflicts).tap {|h| @hotspots_stack.push(h) }
  end

  def collect_hotspots
    initial_size = @hotspots_stack.size
    yield
    @hotspots_stack.pop(@hotspots_stack.size - initial_size)
  end
end

class AlternativeProgramRewriter < Parser::Rewriter
  def initialize(alterations)
    @alterations = alterations
  end

  def on_hotspot(hotspot)
    alternative_for(hotspot).apply_on(self)
    process(hotspot.original_node)
  end

  alias_method :on_comparison_hotspot, :on_hotspot
  alias_method :on_equality_hotspot, :on_hotspot
  alias_method :on_predicate_hotspot, :on_hotspot
  alias_method :on_filter_hotspot, :on_hotspot
  alias_method :on_quantifier_hotspot, :on_hotspot

private
  def alternative_for(hotspot)
    @alterations.fetch(hotspot)
  end
end


class Hotspot < Parser::AST::Node
  extend DescendantsTracker
  attr :conflicts
  
  def self.detect_hotspot_at(node)
    descendants.detect {|subclass| subclass.applies?(node) }
  end

  def self.applies?(node)
    false
  end

  def initialize(node, conflicts: [])
    @conflicts = conflicts
    super(:"#{self.class.name.downcase.chomp('hotspot')}_hotspot", [node])
  end

  def alternatives_mapper
    mappers = alternatives.map {|alter| { self => alter }.compare_by_identity }
    if conflicts.none?
      mappers
    else
      mappers.product(*conflicts.map(&:alternatives_mapper)).
        map {|maps| maps.reduce(:merge) }
    end
  end

  def original_node
    children.first
  end

  def alternatives
    []
  end

  def rewrite(&block)
    Alteration.new(&block)
  end

  class Alteration
    def initialize(&block)
      @transform = block
    end

    def apply_on(rewriter)
      @transform.call(rewriter)
    end
  end
end

class MessageHotspot < Hotspot
  def self.selectors
    []
  end

  def self.applies?(node)
    _, selector = *node
    selectors.detect {|hotspot| hotspot === selector }
  end
end


class OperatorHotspot < MessageHotspot
  def alternatives
    self.class.selectors.map do |sel|
      rewrite {|rw| rw.replace(operator_location, sel.to_s) }
    end
  end

  def operator_location
    original_node.location.selector
  end
end

class ComparisonHotspot < OperatorHotspot
  def self.selectors
    [:>, :>=, :<, :<=]
  end
end

class EqualityHotspot < OperatorHotspot
  def self.selectors
    [:==, :!=]
  end
end

class PredicateHotspot < MessageHotspot
  def self.selectors
    [/\?\Z/]
  end

  def alternatives
    [ rewrite {},
      rewrite {|rw| rw.insert_before(expression_location, '!') } ]
  end

  def expression_location
    original_node.location.expression
  end
end


class BlockHotspot < Hotspot
  def self.selectors
    []
  end

  def alternatives
    self.class.selectors.map do |sel|
      rewrite {|rw| rw.replace(selector_location, sel.to_s) }
    end
  end

  def self.applies?(node)
    expression, _ = *node
    _, selector = *expression
    selectors.detect {|hotspot| hotspot === selector }
  end

  def selector_location
    original_node.to_a.first.location.selector
  end
end

class FilterHotspot < BlockHotspot
  def self.selectors
    [:select, :reject]
  end
end

class QuantifierHotspot < BlockHotspot
  def self.selectors
    [:all?, :none?, :any?, :one?]
  end
end
