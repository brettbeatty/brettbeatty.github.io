---
layout: post
title:  "Enumerable: Custom Data Structures in Elixir, part 1"
date:   2020-09-05 12:00:00 -0600
categories: elixir protocol enumerable
permalink: /elixir/custom_data_structures/enumerable
---
Much of the Elixir language is written in Elixir, and it may surprise you how many data structures
are structs under the hood. Ranges, sets, dates, times--we could build them all ourselves. That's
hidden through their implementation of various protocols provided by Elixir. One way to see what
these data structures look like is to configure IEx to pass an option to the Inspect protocol that
inspects structs like they're maps instead of using their own implementations:
```elixir
iex> IEx.configure(inspect: [structs: false])
:ok

iex> 1..10
%{__struct__: Range, first: 1, last: 10}

iex> MapSet.new([:a, :b, :c])
%{__struct__: MapSet, map: %{a: [], b: [], c: []}, version: 2}

iex> ~D[2020-08-29]
%{__struct__: Date, calendar: Calendar.ISO, day: 29, month: 8, year: 2020}

iex> ~T[15:29:43.867]
%{
  __struct__: Time,
  calendar: Calendar.ISO,
  hour: 15,
  microsecond: {867000, 3},
  minute: 29,
  second: 43
}
```

In this series we're going to create our own array implementation. In addition to coming up with a
sensible API, we will explore various protocols (as well as the Access behaviour) we can implement
to make our arrays more useful.

We aren't going to look too much at what protocols are or how to define our own. For more
information about that, the Elixir [website](https://elixir-lang.org/getting-started/protocols.html)
and [docs](https://hexdocs.pm/elixir/Protocol.html) on the subject are good places to start.

This post will look mostly at [Enumerable](https://hexdocs.pm/elixir/Enumerable.html), the protocol
Elixir provides to standardize resource enumeration. It may seem a strange place to start, but
enumeration will make testing later features easier.

## Array
Lists in Elixir are linked lists, which are great for some operations and less great for others. One
shortcoming is the lack of random access: if we want to access the `:c` in the list `[:a, :b, :c,
:d]`, we have to enumerate the `:a` and `:b` before getting the element we want. Our aim with
implementing arrays is learning over efficiency, but our arrays will have random access. Let's
generate a new project for our array implementation.

### Generate new project
With Elixir [installed](https://elixir-lang.org/install.html), we can use
[mix new](https://hexdocs.pm/mix/Mix.Tasks.New.html) to create a new project. Run `mix new array`
to generate an array project:
```
$ mix new array
* creating README.md
* creating .formatter.exs
* creating .gitignore
* creating mix.exs
* creating lib
* creating lib/array.ex
* creating test
* creating test/test_helper.exs
* creating test/array_test.exs

Your Mix project was created successfully.
You can use "mix" to compile it, test it, and more:

    cd array
    mix test

Run "mix help" for more commands.
$ cd array
```

We will also define the Array struct now to get a general idea of how our arrays will work.

### Define Array struct
To provide random access, our arrays will actually use tuples under the hood. Where tuples have a
known size, we can access any element of the tuple in constant time.

Our Array struct will have three fields:
  - `elements`  
    A tuple containing the elements of the array. This will be at least as large as the number of
    elements in the array, and we'll need to swap it out for a larger tuple whenever we exceed its
    capacity.
  - `size`  
    An integer counting elements in the array. This will increase/decrease as elements are
    added/removed.
  - `start`  
    An integer representing where in the `elements` tuple our array starts. This will
    increase/decrease as elements are removed/added to the front of the array.

Before we define our Array struct, get rid of the existing test; we're going to get rid of
`Array.hello/0`.
```elixir
# test/array_test.exs
defmodule ArrayTest do
  use ExUnit.Case, async: true
end
```

We'll use [defstruct/1](https://hexdocs.pm/elixir/Kernel.html#defstruct/1) to define an Array struct
with fields `:elements`, `:size`, and `:start`, define some
[typespecs](https://hexdocs.pm/elixir/typespecs.html), and document the module and types. 
```elixir
# lib/array.ex
def Array do
  @moduledoc """
  Array is an implementation of arrays in Elixir.

  This module is meant as a learning exercise, not an optimized data structure.
  """

  @typedoc """
  An array with elements of type `element`.
  """
  @opaque t(element) :: %__MODULE__{
            elements: {element} | tuple(),
            size: non_neg_integer(),
            start: non_neg_integer()
          }
  @typedoc """
  An array with elements of any type.
  """
  @type t() :: t(any())

  defstruct ~W[elements size start]a
end
```

The [opaque](https://hexdocs.pm/elixir/typespecs.html#user-defined-types) `t(element)` is so
typespecs can imply what type of elements the array contains. The `elements` will never be a
single-item tuple, but I threw that in there because `_elements` showed up with the underscore in
the docs, and Elixir complains if you don't use a parameter in a type. If you know a better way to
handle that, please [let me know](https://twitter.com/brett_beatty). We also have a `t()` type as a
shortcut to `t(any())`.

## Enumerable
The [Enumerable](https://hexdocs.pm/elixir/Enumerable.html) protocol allows us to define how
resources like our arrays are enumerated. It's how the [Range](https://hexdocs.pm/elixir/Range.html)
module can say the struct `%Range{first: 1, last: 10}` has a size of 10, containing in order the
integers from 1 to 10. Having Enumerable implemented will let us use our arrays with
[Enum](https://hexdocs.pm/elixir/Enum.html) and [Stream](https://hexdocs.pm/elixir/Stream.html)
functions, open us up to using
[comprehensions](https://hexdocs.pm/elixir/Kernel.SpecialForms.html#for/1), and ease conversion to
other collections (functions like [Map.new/1](https://hexdocs.pm/elixir/Map.html#new/1) and
[MapSet.new/1](https://hexdocs.pm/elixir/MapSet.html#new/1) take enumerables).

Enumerable has four functions to implement:
  - [count/1](https://hexdocs.pm/elixir/Enumerable.html#count/1)
  - [member?/2](https://hexdocs.pm/elixir/Enumerable.html#member?/2)
  - [reduce/3](https://hexdocs.pm/elixir/Enumerable.html#reduce/3)
  - [slice/1](https://hexdocs.pm/elixir/Enumerable.html#slice/1)

We'll cover each in its own section, but the most important function to implement is `reduce/3`; the
others exist for optimization only and can defer to implementations built on `reduce/3`. We'll start
with `reduce/3`, which will rely on a function we'll call `shift/1`.

### Define Array.shift/1
For lack of a better name I borrowed "shift" from JavaScript's
[Array.prototype.shift()](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/shift).
This function will remove the first element from an array and return a tuple containing `:ok`, the
first element, and the updated array. For empty arrays it will return `:error`. Let's start with a
couple tests.
```elixir
defmodule ArrayTest do
  use ExUnit.Case, async: true

  describe "shift/1" do
    test "shifts the first element off an array" do
      array = %Array{elements: {:b, :a}, size: 2, start: 1}
      expected_array = %Array{elements: {:b, :a}, size: 1, start: 0}

      assert {:ok, :a, ^expected_array} = Array.shift(array)
    end

    test "returns :error when shifting off an empty array" do
      array = %Array{elements: {nil, nil}, size: 0, start: 0}

      assert Array.shift(array) == :error
    end
  end
end
```

Our `shift/1` function will need a private function `element_position/1` to make our `elements`
tuple "cyclic". If we give it a position out of the tuple's bounds, we want it to add or subtract
multiples of the tuple's size to give us a position within the tuple's bounds. This means, for
example, if we give it a position of 9 when our tuple only has a size of 8, the position will be
instead 1. Our implementation will use [rem/2](https://hexdocs.pm/elixir/Kernel.html#rem/2) to limit
everything to the capacity. We want to support negative positions, too, so we'll add again the
capacity so we don't end up with a negative in our result.
```elixir
defmodule Array do
  # ...

  @spec element_position(t(), integer()) :: non_neg_integer()
  defp element_position(array, index) do
    capacity = tuple_size(array.elements)

    case rem(array.start + index, capacity) do
      remainder when remainder >= 0 ->
        remainder

      remainder ->
        remainder + capacity
    end
  end
end
```

Now let's define `shift/1`. We'll take advantage of pattern matching on the size to handle our
branch condition. If the size is 0, we return `:error`. Otherwise we grab the element, decrement the
array size, and increment the start position of the array, wrapping it around if it exceeds the
bounds of the tuple. For the wrapping of the start position, we'll use our `element_position/2`
function we just defined.
```elixir
defmodule Array do
  # ...

  @doc """
  Shifts the first element from an array, returning it and the updated array.

  Returns :error if array is empty.

  ## Examples

      iex> array = Array.new([:z, :a, :b, :c])
      iex> {:ok, :z, new_array} = Array.shift(array)
      iex> new_array
      #Array<[:a, :b, :c]>

      iex> array = Array.new()
      iex> Array.shift(array)
      :error

  """
  @spec shift(array :: t(element)) :: {:ok, element, t(element)} | :error when element: var
  def shift(array)

  def shift(%{size: 0}) do
    :error
  end

  def shift(array) do
    element = elem(array.elements, array.start)
    new_array = %{array | size: array.size - 1, start: element_position(array, 1)}

    {:ok, element, new_array}
  end
end
```

The examples in the docstring suggest what our arrays could soon be, but we aren't there yet.
However, if we run the tests we just wrote, they should pass.
```
$ mix test
Compiling 1 file (.ex)
..

Finished in 0.03 seconds
2 tests, 0 failures

Randomized with seed 610372
```

Now that we have `shift/1` written we can begin to implement Enumerable.

### Implement Enumerable.reduce/3
[Enumerable.reduce/3](https://hexdocs.pm/elixir/Enumerable.html#reduce/3) is perhaps the most
difficult to understand of any callbacks we'll cover in this series (it was for me). It takes three
arguments:
  - `enumerable`  
    An enumerable resource for which Enumerable is implemented. In our case this will always be an
    array.
  - `command`  
    A signal whether to keep enumerating the structure. The Enumerable docs call it `acc`, but they
    also use `acc` for the value inside the command passed to the reducer, so I've called it
    `command` for disambiguation. The command can have three forms:
    - `{:cont, acc}`  
      Get/reduce the next value. This command should result in a `{:done, acc}` if the enumerable is
      empty or a call to the reducer to get the next command (typically next command is passed to a
      recursive call to `reduce/3` or a helper function).
    - `{:halt, acc}`  
      Stop enumerating. This command exists to allow enumerables to perform cleanup if needed. It
      should result in `{:halted, acc}`.
    - `{:suspend, acc}`  
      Temporarily pause enumeration. Enumerable won't be left in this state; the protocol expects
      the caller to eventually resume or halt enumeration. This command should result in a
      `{:suspended, acc, continuation}` where `continuation` is a function that takes a command and
      resumes things (similar to the recursive call for a `:cont` command).
  - `reducer`  
    A function that takes the next element and the acc and returns a new command.

It's a little confusing, but I think the best thing for me to understand it all was reading
implementations for built-in enumerables
([Range](https://github.com/elixir-lang/elixir/blob/v1.10.4/lib/elixir/lib/range.ex#L102),
[Map](https://github.com/elixir-lang/elixir/blob/v1.10.4/lib/elixir/lib/enum.ex#L3700), etc.) and
writing some of my own. Here's what it could look like for our Array module:
```elixir
defmodule Array do
  # ...

  defimpl Enumerable do
    @impl Enumerable
    def count(_array) do
      {:error, __MODULE__}
    end

    @impl Enumerable
    def member?(_array, _element) do
      {:error, __MODULE__}
    end

    @impl Enumerable
    def reduce(array, acc, fun)

    def reduce(array, {:cont, acc}, fun) do
      case Array.shift(array) do
        {:ok, element, new_array} ->
          reduce(new_array, fun.(element, acc), fun)

        :error ->
          {:done, acc}
      end
    end

    def reduce(_array, {:halt, acc}, _fun) do
      {:halted, acc}
    end

    def reduce(array, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce(array, &1, fun)}
    end

    @impl Enumerable
    def slice(_array) do
      {:error, __MODULE__}
    end
  end
end
```
For `count/1`, `member?/2`, and `slice/1`, you may notice we're just returning
`{:error, __MODULE__}`. This is how we signal that we just want each of those to fall back to
the default implementation based on `reduce/3`.

When `reduce/3` is called with `:cont`, we try to shift the first element off the array. If we get
back an element and updated array, we get a new command by calling the reducer with the element and
accumulator. We then pass the command to a recursive call to `reduce/3` with the updated array and
the reducer. If instead we get a `:halt`, we don't have any cleanup to do, so we can just return
`{:halted, acc}`. If we get a `:suspend`, we create an anonymous function that takes a command and
calls `reduce/3` with the array, command, and reducer function, and we return a `{:suspended, acc,
continuation}` tuple.

Rather than testing our Enumerable implementation directly, we'll use functions from `Enum` to check
the handshake works as expected:
  - [Enum.map/2](https://hexdocs.pm/elixir/Enum.html#map/2) relies on the reducer function to map
    values. It also goes entirely through the enumerable and will check our empty array path will
    work as expected.
  - [Enum.take/2](https://hexdocs.pm/elixir/Enum.html#take/2) halts enumeration once it has as many
    elements as it needs.
  - [Enum.zip/2](https://hexdocs.pm/elixir/Enum.html#zip/2) suspends and resumes enumerables to take
    an element at a time.

```elixir
defmodule ArrayTest do
  # ...

  describe "Enumerable" do
    test "passes everything appropriately to reducer" do
      array = %Array{elements: {?c, ?d, ?a, ?b}, size: 3, start: 2}

      assert Enum.map(array, &(&1 + 4)) == 'efg'
    end

    test "halts early just fine" do
      array = %Array{elements: {?w, ?x, ?y, ?z}, size: 4, start: 0}

      assert Enum.take(array, 2) == 'wx'
    end

    test "suspends and resumes" do
      array = %Array{elements: {:b, :c, :d, :a}, size: 3, start: 3}

      assert Enum.zip(array, 1..3) == [a: 1, b: 2, c: 3]
    end
  end
end
```

Checking our tests pass, we can now optimize other Enumerable operations. We'll start with
`count/1`, but to shield our Enumerable implementation from the Array internals, let's create a
quick `Array.size/1` function.

### Define Array.size/1
Where we have the array size directly in the struct, this will be an easy function to write. Let's
start with a test.
```elixir
defmodule ArrayTest do
  # ...

  describe "size/1" do
    test "returns the size of the array" do
      array = %Array{elements: {?a, ?b, ?c, ?d}, size: 2, start: 1}

      assert Array.size(array) == 2
    end
  end

  # ...
end
```

The function we can implement in a single line.
```elixir
defmodule Array do
  # ...

  @doc """
  Returns the size of an array.

  ## Examples

      iex> array = Array.new([:a, :b, :c])
      iex> Array.size(array)
      3

  """
  @spec size(array :: t()) :: non_neg_integer()
  def size(array) do
    array.size
  end

  # ...
end
```

That test should pass. Now let's implement `Enumerable.count/1`.

### Implement Enumerable.count/1
[Enumerable.count/1](https://hexdocs.pm/elixir/Enumerable.html#count/1) is used to count the
elements in an enumerable. The default implementation to which we're falling back has to traverse
the entire enumerable to count its elements. Enumerable allows us to implement a more efficient
alternative if one exists for our data structure. Of course the size of our arrays are already
known, so that's much more efficient, and we should implement `count/1`. Let's write a test to make
sure we don't break anything.
```elixir
defmodule ArrayTest do
  # ...

  describe "Enumerable" do
    test "count is accurate" do
      array = %Array{elements: {nil, nil, nil, nil}, size: 1, start: 0}

      assert Enum.count(array) == 1
    end

    # ...
  end
end
```

That test should already pass, but it should still pass when we implement `count/1`. Our
implementation should take an array and return `{:ok, count}`. Fortunately that's pretty easy with
our `Array.size/1` function.
```elixir
defmodule Array do
  # ...

  defimpl Enumerable do
    @impl Enumerable
    def count(array) do
      {:ok, Array.size(array)}
    end

    # ...
  end
end
```

We can check now that the test still passes, and it does. Now let's look at `Enumerable.member?/2`.

### Consider Enumerable.member?/2
When we ask whether an element is within an enumerable, the default `reduce/3`-based implementation
of [member?/2](https://hexdocs.pm/elixir/Enumerable.html#member?/2) traverses the enumerable until
it finds the element or gets through the entire thing without finding it. Some enumerables can
provide a better approach. Ranges, for example, can check if a value is in the range by making sure
it's an integer between the first and last integers in the range.

Is there a way for our arrays to check membership more efficiently? If we were checking if an index
was in the appropriate range, that would be fairly easy (and we might actually do that in a later
post). However, there's not a great way to look for a value in a tuple without looking at every
element. Since tuples are how our arrays store elements, the default implementation is about as good
as membership checks are going to get.

We can, however, provide a better implementation for our last Enumerable function, `slice/1`, so
let's check that out. Like we did with `count/1`, let's add a function to Array's public API to make
`slice/1` easier to implement.

### Define Array.slice/3
This function will take an array, an index for where to begin slicing, and a number of elements to
include in our slice. Since our array struct uses a `start` and a `size` to bound it, we won't even
need to touch an array's `elements` when making a slice. Let's add a couple tests to make sure our
slices look like we'd expect.
```elixir
defmodule ArrayTest do
  # ...

  describe "slice/3" do
    test "returns a slice of an array" do
      array = %Array{elements: {:a, :b, :c, :d}, size: 4, start: 3}
      expected_array = %Array{elements: {:a, :b, :c, :d}, size: 2, start: 0}

      assert Array.slice(array, 1, 2) == expected_array
    end

    test "does not allow a slice past end of array" do
      array = %Array{elements: {:a, :b, :c, :d}, size: 4, start: 0}
      expected_array = %Array{elements: {:a, :b, :c, :d}, size: 2, start: 2}

      assert Array.slice(array, 2, 4) == expected_array
    end
  end

  # ...
end
```

The slice's start is the sum of the array start and the start passed to the function, wrapped if it
exceeds the array's capacity. For that we can use `element_position/2` we defined earlier. The size
is the size passed in limited to the number of elements remaining between the start and end of the
original array. Enumerable will limit the size for us when this function is called through
`Enumerable.slice/1`, but we're limiting it here for when it's called directly.
```elixir
defmodule Array do
  # ...

  @doc """
  Slices an array with `size` elements from the old array starting at `index`.

  ## Examples

      iex> array = Array.new([:y, :z, :a, :b, :c, :d])
      iex> Array.slice(array, 2, 3)
      #Array<[:a, :b, :c]>

      iex> array = Array.new([:z, :a, :b, :c])
      iex> Array.slice(array, 1, 7)
      #Array<[:a, :b, :c]>

  """
  @spec slice(array :: t(element), start :: non_neg_integer(), size :: non_neg_integer()) ::
          t(element)
        when element: var
  def slice(array, start, size) do
    %{array | start: element_position(array, start), size: min(size, array.size - start)}
  end

  # ...
end
```

Before we implement `Enumerable.slice/1`, we have a problem: our `Array.slice/3` function returns an
array, but `Enumerable.slice/1` is going to want a list. Let's give our arrays a `to_list/1`
function.

### Define Array.to_list/1
Since we have `Enumerable.reduce/3` implemented, turning arrays into lists is going to be easy.
First, a test.
```elixir
defmodule ArrayTest do
  # ...

  describe "to_list/1" do
    test "converts an array to a list" do
      array = %Array{elements: {?a, ?b, ?c, ?d}, size: 3, start: 1}

      assert Array.to_list(array) == 'bcd'
    end
  end

  # ...
end
```

There's a function `Enum.to_list/1` that converts any enumerable to a list.
```elixir
defmodule Array do
  # ...

  @doc """
  Converts an array to a list.

  ## Examples

      iex> array = Array.new([:a, :b, :c])
      iex> Array.to_list(array)
      [:a, :b, :c]

  """
  @spec to_list(array :: t(element)) :: [element] when element: var
  def to_list(array) do
    Enum.to_list(array)
  end

  # ...
end
```

Now that we have `Array.slice/3` and `Array.to_list/1` implemented, let's finally implement
`Enumerable.slice/1`.

### Implement Enumerable.slice/1
[Enumerable.slice/1](https://hexdocs.pm/elixir/Enumerable.html#slice/1) is used for getting a list
of contiguous elements from somewhere in an enumerable.  Before we get into how it works, let's
write a test. Again, this should already pass.
```elixir
defmodule ArrayTest do
  # ...

  describe "Enumerable" do
    # ...

    test "slices work as expected" do
      array = %Array{elements: {?a, ?b, ?c, ?d}, size: 4, start: 2}

      assert Enum.slice(array, 1, 2) == 'da'
    end
  end
end
```

Rather than slicing our array immediately like `Array.slice/3`, `Enumerable.slice/1` takes an
enumerable and returns a size and a function. The size is used to not request more elements than are
present in the enumerable. The function takes a start and a length and returns a list of elements.
Usually it'll be an anonymous wrapper currying a different slice function with the enumerable.
That's what we're going to do.
```elixir
defmodule Array do
  # ...

  defimpl Enumerable do
    # ...

    @impl Enumerable
    def slice(array) do
      {:ok, Array.size(array), &Array.to_list(Array.slice(array, &1, &2))}
    end
  end
end
```

And there you go! We have now implemented all the Enumerable functions we can.

## Cleanup & Review
Before we conclude here, let's clean up a few of our tests.

### Use Array.to_list/1 in tests
Ideally our tests would worry less about array internals and more about their public API. We won't
be able to avoid creating struct literals until we've implemented `Array.new/1` in the next post of
this series, but we can move away from comparing updated arrays to a literal and instead check our
arrays by their list equivalents. Here's what our tests could look like with those changes.
```elixir
# test/array_test.exs
defmodule ArrayTest do
  use ExUnit.Case, async: true

  describe "shift/1" do
    test "shifts the first element off an array" do
      array = %Array{elements: {:b, :a}, size: 2, start: 1}

      assert {:ok, :a, new_array} = Array.shift(array)
      assert Array.to_list(new_array) == [:b]
    end

    test "returns :error when shifting off an empty array" do
      array = %Array{elements: {nil, nil}, size: 0, start: 0}

      assert Array.shift(array) == :error
    end
  end

  describe "size/1" do
    test "returns the size of the array" do
      array = %Array{elements: {?a, ?b, ?c, ?d}, size: 2, start: 1}

      assert Array.size(array) == 2
    end
  end

  describe "slice/3" do
    test "returns a slice of an array" do
      array = %Array{elements: {:a, :b, :c, :d}, size: 4, start: 3}
      array = Array.slice(array, 1, 2)

      assert Array.to_list(array) == [:a, :b]
    end

    test "does not allow a slice past end of array" do
      array = %Array{elements: {:a, :b, :c, :d}, size: 4, start: 0}
      array = Array.slice(array, 2, 4)

      assert Array.to_list(array) == [:c, :d]
    end
  end

  describe "to_list/1" do
    test "converts an array to a list" do
      array = %Array{elements: {?a, ?b, ?c, ?d}, size: 3, start: 1}

      assert Array.to_list(array) == 'bcd'
    end
  end

  describe "Enumerable" do
    test "count is accurate" do
      array = %Array{elements: {nil, nil, nil, nil}, size: 1, start: 0}

      assert Enum.count(array) == 1
    end

    test "passes everything appropriately to reducer" do
      array = %Array{elements: {?c, ?d, ?a, ?b}, size: 3, start: 2}

      assert Enum.map(array, &(&1 + 4)) == 'efg'
    end

    test "halts early just fine" do
      array = %Array{elements: {?w, ?x, ?y, ?z}, size: 4, start: 0}

      assert Enum.take(array, 2) == 'wx'
    end

    test "suspends and resumes" do
      array = %Array{elements: {:b, :c, :d, :a}, size: 3, start: 3}

      assert Enum.zip(array, 1..3) == [a: 1, b: 2, c: 3]
    end

    test "slices work as expected" do
      array = %Array{elements: {?a, ?b, ?c, ?d}, size: 4, start: 2}

      assert Enum.slice(array, 1, 2) == 'da'
    end
  end
end
```

If you want to compare Array modules now, here's what it could look like.
```elixir
# lib/array.ex
defmodule Array do
  @moduledoc """
  Array is an implementation of arrays in Elixir.

  This module is meant as a learning exercise, not an optimized data structure.
  """

  @typedoc """
  An array with elements of type `element`.
  """
  @opaque t(element) :: %__MODULE__{
            elements: {element} | tuple(),
            size: non_neg_integer(),
            start: non_neg_integer()
          }
  @typedoc """
  An array with elements of any type.
  """
  @type t() :: t(any())

  defstruct ~W[elements size start]a

  @spec element_position(t(), integer()) :: non_neg_integer()
  defp element_position(array, index) do
    capacity = tuple_size(array.elements)

    case rem(array.start + index, capacity) do
      remainder when remainder >= 0 ->
        remainder

      remainder ->
        remainder + capacity
    end
  end

  @doc """
  Shifts the first element from an array, returning it and the updated array.

  Returns :error if array is empty.

  ## Examples

      iex> array = Array.new([:z, :a, :b, :c])
      iex> {:ok, :z, new_array} = Array.shift(array)
      iex> new_array
      #Array<[:a, :b, :c]>

      iex> array = Array.new()
      iex> Array.shift(array)
      :error

  """
  @spec shift(array :: t(element)) :: {:ok, element, t(element)} | :error when element: var
  def shift(array)

  def shift(%{size: 0}) do
    :error
  end

  def shift(array) do
    element = elem(array.elements, array.start)
    new_array = %{array | size: array.size - 1, start: element_position(array, 1)}

    {:ok, element, new_array}
  end

  @doc """
  Returns the size of an array.

  ## Examples

      iex> array = Array.new([:a, :b, :c])
      iex> Array.size(array)
      3

  """
  @spec size(array :: t()) :: non_neg_integer()
  def size(array) do
    array.size
  end

  @doc """
  Slices an array with `size` elements from the old array starting at `index`.

  ## Examples

      iex> array = Array.new([:y, :z, :a, :b, :c, :d])
      iex> Array.slice(array, 2, 3)
      #Array<[:a, :b, :c]>

      iex> array = Array.new([:z, :a, :b, :c])
      iex> Array.slice(array, 1, 7)
      #Array<[:a, :b, :c]>

  """
  @spec slice(array :: t(element), start :: non_neg_integer(), size :: non_neg_integer()) ::
          t(element)
        when element: var
  def slice(array, start, size) do
    %{array | start: element_position(array, start), size: min(size, array.size - start)}
  end

  @doc """
  Converts an array to a list.

  ## Examples

      iex> array = Array.new([:a, :b, :c])
      iex> Array.to_list(array)
      [:a, :b, :c]

  """
  @spec to_list(array :: t(element)) :: [element] when element: var
  def to_list(array) do
    Enum.to_list(array)
  end

  defimpl Enumerable do
    @impl Enumerable
    def count(array) do
      {:ok, Array.size(array)}
    end

    @impl Enumerable
    def member?(_array, _element) do
      {:error, __MODULE__}
    end

    @impl Enumerable
    def reduce(array, acc, fun)

    def reduce(array, {:cont, acc}, fun) do
      case Array.shift(array) do
        {:ok, element, new_array} ->
          reduce(new_array, fun.(element, acc), fun)

        :error ->
          {:done, acc}
      end
    end

    def reduce(_array, {:halt, acc}, _fun) do
      {:halted, acc}
    end

    def reduce(array, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce(array, &1, fun)}
    end

    @impl Enumerable
    def slice(array) do
      {:ok, Array.size(array), &Array.to_list(Array.slice(array, &1, &2))}
    end
  end
end
```

## Conclusion
The Enumerable protocol can be a bit tricky to understand, but its API provides for some powerful
enumerables. If you want to learn more about it, I'd recommend checking out the source code for
existing implementations and writing your own. It can also be helpful to write your own Enum
functions that interact with enumerables through the Enumerable module directly.

Follow me on [Twitter](https://twitter.com/brett_beatty) to be alerted when I publish future posts
in my "Custom Data Structures in Elixir" series.

### Fun Tidbit: Enumerable Functions
In the elixir source there's an interesting bit of code: an [Enumerable implementation for
functions](https://github.com/elixir-lang/elixir/blob/v1.10.4/lib/elixir/lib/enum.ex#L3723). It
turns out you can have an enumerable function of arity 2 that takes a command and reducer (like if
our `reduce/3` was not passed an array). That lets you do things like this:
```elixir
defmodule Counter do
  @spec counter(start :: integer(), step :: integer()) :: Enumerable.t()
  def counter(start, step) do
    &do_counter(&1, start, step, &2)
  end

  @spec do_counter(
          command :: Enumerable.acc(),
          value :: integer(),
          step :: integer(),
          reducer :: Enumerable.reducer()
        ) :: Enumerable.result()
  defp do_counter(command, value, step, reducer)

  defp do_counter({:cont, acc}, value, step, reducer) do
    value
    |> reducer.(acc)
    |> do_counter(value + step, step, reducer)
  end

  defp do_counter({:halt, acc}, _value, _step, _reducer) do
    {:halted, acc}
  end

  defp do_counter({:suspend, acc}, value, step, reducer) do
    {:suspend, acc, &do_counter(&1, value, step, reducer)}
  end
end

Counter.counter(1, 3)
#=> #Function<0.94376427/2 in Counter.counter/2>

Counter.counter(1, 3) |> Enum.take(5)
#=> [1, 4, 7, 10, 13]

Counter.counter(?z, -1) |> Enum.take(26)
#=> 'zyxwvutsrqponmlkjihgfedcba'
```
