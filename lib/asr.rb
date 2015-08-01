require 'unparser'
require 'minitest'
require 'diffy'
require 'descendants_tracker'

require 'pry'

module Minitest
  # Disable autorun from test files
  @@installed_at_exit = true
end

class SoftwareAutoRepair
  attr_reader :program_template, :conflicts_graph
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
    each_alternatives_mapper do |mapper|
      alternative_ast = AlternativeProgramsGenerator.new(mapper).process(program_template)
      yield Unparser.unparse(alternative_ast)
    end
  end

private
  def print_fix(variant)
    puts "Generated fix for failing tests:\n"
    puts Diffy::Diff.new(@code, variant, context: 3, include_diff_info: true).to_s(:color).
      sub(%r{--- /tmp/diffy.[^\n]+}, '--- original file').
      sub(%r{\+\+\+ /tmp/diffy.[^\n]+}, '+++ fixed file')
  end

  def as_ast(code)
    Parser::CurrentRuby.parse(code)
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
    @program_template = detector.process(as_ast(@code)).tap { @conflicts_graph = detector.detected_conflicts }
  end

  def each_alternatives_mapper(&bl)
    first, *rest = conflicts_graph.map(&:alternatives_mapper)
    rest.empty? ? first.each(&bl) : first.product(*rest) {|mappers| yield mappers.reduce(&:merge) }
  end
end

class HotspotsDetector < Parser::AST::Processor
  def initialize
    @hotspots_stack = []
  end

  def detected_conflicts
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


class AlternativeProgramsGenerator < Parser::AST::Processor
  def initialize(alternatives_mapper)
    @alternatives = alternatives_mapper
  end

  def on_hotspot(hotspot)
    updated_node = process(hotspot.original_node)
    apply_alternative(updated_node, hotspot)
  end

private
  def apply_alternative(node, hotspot)
    @alternatives.fetch(hotspot).call(node)
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
    super(:hotspot, [node])
  end

  def alternatives
    -> node { node }
  end

  def alternatives_mapper
    mappers = alternatives.map {|alter| { self => alter }.compare_by_identity }
    if conflicts.none?
      mappers
    else
      mappers.product(*conflicts.map(&:alternatives_mapper)).map {|mapper, *conflict_mappers| conflict_mappers.reduce(mapper.dup, :merge!) }
    end
  end

  def original_node
    children.first
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
    self.class.selectors.map do |new_sel|
      -> node { alternative_node_using(node, new_sel) }
    end
  end

  def alternative_node_using(node, new_sel)
    rec, _sel, *args = *node
    node.updated(nil, [rec, new_sel, *args])
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
    [ -> node { node },
      -> node { Parser::AST::Node.new(:send, [node, :!]) } ]
  end
end

class BlockHotspot < Hotspot
  def self.selectors
    []
  end

  def self.applies?(node)
    expression, _ = *node
    _, selector = *expression
    selectors.detect {|hotspot| hotspot === selector }
  end

  def alternatives
    self.class.selectors.map do |new_sel|
      -> node { alternative_node_using(node, new_sel) }
    end
  end

  def alternative_node_using(node, new_sel)
    exp, *rest = *node
    rec, _sel, *args = *exp
    new_exp = exp.updated(nil, [rec, new_sel, *args])

    node.updated(nil, [new_exp, *rest])
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
