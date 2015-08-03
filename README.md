## Prototype for an Automatic Software Repair Tool for Ruby

### General idea

The inspiration for our idea was to try to experiment with bug hotspots on languages like Ruby or Smalltalk where you usually don't make use of some programming constructs like `if`, `for` or `while` like in C or often Java, but instead you rely on specific idioms or protocols or try to exploit polymorphism instead. To give an example: for iterating over elements on a collection you use `each` in Ruby (or `do:` in Smalltalk) instead of a `for` loop, for filtering elements from a list you use `select` or `reject` with a predicate as a parameter, for calculating an acumulative result from each element of a collection `inject` (or `reduce`) is often used, and so on.

In our prototype we implement bug fixing techniques for some of the hotspots proposed at [Automatic Error Correction of Java Programs](http://link.springer.com/chapter/10.1007%2F978-3-642-15898-8_5#page-1) paper for comparison and equality operators, plus some others of our own creation, that detect some common Ruby protocols from which we believe usual bugs potentially stem.

Since we assume that `if` (and `while`) expressions are rather seldom (or at least less common that in, say, Java), and to make things worse Ruby and Smalltalk don't have static types you could use to find conditional predicates, we will exploit the fact that in dynamic languages a vocabulary of messages is built where 2 methods with the same name will have polymorphic equivalent behavior and follow similar semantics regardless of the class they are in (as we said before about `each`, `select`, etc...). So for instance you can assume quite confidently what the block passed in a `select` or `all?` message is a predicate. Also methods which name ends with a `?` character in Ruby returns booleans by convention (that is they are predicates) and we could try negating them.

The specific Ruby hotspots we detect and try to fix at the prototype, are `select`/`reject` methods, which we try interchanging to fix the bug, boolean query methods and existential and universal quantifier (`any?` and `all?` in Ruby), for which we try every combination they can be arranged at the places we find them.

### Description

The program takes a Ruby program and a test suite and runs it against the input program. If errors are found, the program will attempt to generate a patch to fix it and make all test cases pass. To do this, the code is converted to an AST and sent to a hotspot detector. This detector can analyze the nodes of the program and generate a template (like in the in [Automatic Error Correction of Java Programs](http://link.springer.com/chapter/10.1007%2F978-3-642-15898-8_5#page-1) paper), this template will have all the analyzed hotspots. Each hotspot knows all of its alternatives and the other hotspots they are in conflict with, therefore, we can generate a new variant simply by iterating each alternative for each hotspot and taking the conflicts into account. Thus, for each variant, we run the test suite again, until the program finds a valid variant that makes all tests pass, or it runs out of variants.

For our prototype, we have two different implementations of a program, one uses Ruby blocks and a rather more idiomatic code to iterate and the other one iterates manually (i.e. using a plain old `for` loop), each one has a bug that makes the test suite fail. Both implementations can be patched by our program, it will produce a diff output showing which line has the bug and the fix it has found for it.


### How to use

Ruby 2.1 or newer is required.

First, install the required gems with:

    bundle install

Then verify that tests are failing with:

    rake test

To fix the programs, run:

    bin/fix_ruby lib/asr/mylib_idiom.rb test/test_mylib_idiom.rb       # to patch the idiomatic version
    bin/fix_ruby lib/asr/mylib_imp.rb test/test_mylib_imp.rb           # to patch the iterative version
