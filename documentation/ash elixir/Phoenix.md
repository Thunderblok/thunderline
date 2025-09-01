# phoenix_live_view

> Rich, real-time user experiences with server-rendered HTML

## Docs

### Phoenix.Component (module)

Define reusable function components with HEEx templates.

A function component is any function that receives an assigns
map as an argument and returns a rendered struct built with
[the `~H` sigil](`sigil_H/2`):

    defmodule MyComponent do
      # In Phoenix apps, the line is typically: use MyAppWeb, :html
      use Phoenix.Component

      def greet(assigns) do
        ~H"""
         Hello, {@name}! 
        """
      end
    end

This function uses the `~H` sigil to return a rendered template.
`~H` stands for HEEx (HTML + EEx). HEEx is a template language for
writing HTML mixed with Elixir interpolation. We can write Elixir
code inside `{...}` for HTML-aware interpolation inside tag attributes
and the body. We can also interpolate arbitrary HEEx blocks using `<%= ... %>`
We use `@name` to access the key `name` defined inside `assigns`.

When invoked within a `~H` sigil or HEEx template file:

```heex
 
```

The following HTML is rendered:

```html
 Hello, Jane! 
```

If the function component is defined locally, or its module is imported,
then the caller can invoke the function directly without specifying the module:

```heex
<.greet name="Jane" />
```

For dynamic values, you can interpolate Elixir expressions into a function component:

```heex
<.greet name={@user.name} />
```

Function components can also accept blocks of HEEx content (more on this later):

```heex
<.card>
   This is the body of my card! 
</.card>
```

In this module we will learn how to build rich and composable components to
use in our applications.

### Attributes - Phoenix.Component (module)

`Phoenix.Component` provides the `attr/3` macro to declare what attributes the proceeding function
component expects to receive when invoked:

    attr :name, :string, required: true

    def greet(assigns) do
      ~H"""
       Hello, {@name}! 
      """
    end

By calling `attr/3`, it is now clear that `greet/1` requires a string attribute called `name`
present in its assigns map to properly render. Failing to do so will result in a compilation
warning:

```heex
 
  <!-- warning: missing required attribute "name" for component MyAppWeb.MyComponent.greet/1
           lib/app_web/my_component.ex:15 -->
```

Attributes can provide default values that are automatically merged into the assigns map:

    attr :name, :string, default: "Bob"

Now you can invoke the function component without providing a value for `name`:

```heex
<.greet />
```

Rendering the following HTML:

```html
 Hello, Bob! 
```

Accessing an attribute which is required and does not have a default value will fail.
You must explicitly declare `default: nil` or assign a value programmatically with the
`assign_new/3` function.

Multiple attributes can be declared for the same function component:

    attr :name, :string, required: true
    attr :age, :integer, required: true

    def celebrate(assigns) do
      ~H"""
       
        Happy birthday {@name}!
        You are {@age} years old.
       
      """
    end

Allowing the caller to pass multiple values:

```heex
<.celebrate name={"Genevieve"} age={34} />
```

Rendering the following HTML:

```html
 
  Happy birthday Genevieve!
  You are 34 years old.
 
```

Multiple function components can be defined in the same module, with different attributes. In the
following example, ` ` requires a `name`, but *does not* require a `title`, and
` ` requires a `title`, but *does not* require a `name`.

    defmodule Components do
      # In Phoenix apps, the line is typically: use MyAppWeb, :html
      use Phoenix.Component

      attr :title, :string, required: true

      def heading(assigns) do
        ~H"""
         {@title} 
        """
      end

      attr :name, :string, required: true

      def greet(assigns) do
        ~H"""
         Hello {@name} 
        """
      end
    end

With the `attr/3` macro you have the core ingredients to create reusable function components.
But what if you need your function components to support dynamic attributes, such as common HTML
attributes to mix into a component's container?

### Global attributes - Phoenix.Component (module)

Global attributes are a set of attributes that a function component can accept when it
declares an attribute of type `:global`. By default, the set of attributes accepted are those
attributes common to all standard HTML tags.
See [Global attributes](https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes)
for a complete list of attributes.

Once a global attribute is declared, any number of attributes in the set can be passed by
the caller without having to modify the function component itself.

Below is an example of a function component that accepts a dynamic number of global attributes:

    attr :message, :string, required: true
    attr :rest, :global

    def notification(assigns) do
      ~H"""
       {@message} 
      """
    end

The caller can pass multiple global attributes (such as `phx-*` bindings or the `class` attribute):

```heex
<.notification message="You've got mail!" class="bg-green-200" phx-click="close" />
```

Rendering the following HTML:

```html
 You've got mail! 
```

Note that the function component did not have to explicitly declare a `class` or `phx-click`
attribute in order to render.

Global attributes can define defaults which are merged with attributes provided by the caller.
For example, you may declare a default `class` if the caller does not provide one:

    attr :rest, :global, default: %{class: "bg-blue-200"}

Now you can call the function component without a `class` attribute:

```heex
<.notification message="You've got mail!" phx-click="close" />
```

Rendering the following HTML:

```html
 You've got mail! 
```

Note that the global attribute cannot be provided directly and doing so will emit
a warning. In other words, this is invalid:

```heex
<.notification message="You've got mail!" rest={%{"phx-click" => "close"}} />
```

### Included globals - Phoenix.Component (module)

You may also specify which attributes are included in addition to the known globals
with the `:include` option. For example to support the `form` attribute on a button
component:

```elixir
# <.button form="my-form"/>
attr :rest, :global, include: ~w(form)
slot :inner_block
def button(assigns) do
  ~H"""
   {render_slot(@inner_block)} 
  """
end
```

The `:include` option is useful to apply global additions on a case-by-case basis,
but sometimes you want to extend existing components with new global attributes,
such as Alpine.js' `x-` prefixes, which we'll outline next.

### Custom global attribute prefixes - Phoenix.Component (module)

You can extend the set of global attributes by providing a list of attribute prefixes to
`use Phoenix.Component`. Like the default attributes common to all HTML elements,
any number of attributes that start with a global prefix will be accepted by function
components invoked by the current module. By default, the following prefixes are supported:
`phx-`, `aria-`, and `data-`. For example, to support the `x-` prefix used by
[Alpine.js](https://alpinejs.dev/), you can pass the `:global_prefixes` option to
`use Phoenix.Component`:

    use Phoenix.Component, global_prefixes: ~w(x-)

In your Phoenix application, this is typically done in your
`lib/my_app_web.ex` file, inside the `def html` definition:

    def html do
      quote do
        use Phoenix.Component, global_prefixes: ~w(x-)
        # ...
      end
    end

Now all function components invoked by this module will accept any number of attributes
prefixed with `x-`, in addition to the default global prefixes.

You can learn more about attributes by reading the documentation for `attr/3`.

### Slots - Phoenix.Component (module)

In addition to attributes, function components can accept blocks of HEEx content, referred to
as slots. Slots enable further customization of the rendered HTML, as the caller can pass the
function component HEEx content they want the component to render. `Phoenix.Component` provides
the `slot/3` macro used to declare slots for function components:

    slot :inner_block, required: true

    def button(assigns) do
      ~H"""
       
        {render_slot(@inner_block)}
       
      """
    end

The expression `render_slot(@inner_block)` renders the HEEx content. You can invoke this function
component like so:

```heex
<.button>
  This renders  inside  the button!
</.button>
```

Which renders the following HTML:

```html
 
  This renders  inside  the button!
 
```

Like the `attr/3` macro, using the `slot/3` macro will provide compile-time validations.
For example, invoking `button/1` without a slot of HEEx content will result in a compilation
warning being emitted:

```heex
<.button />
  <!-- warning: missing required slot "inner_block" for component MyAppWeb.MyComponent.button/1
           lib/app_web/my_component.ex:15 -->
```

### The default slot - Phoenix.Component (module)

The example above uses the default slot, accessible as an assign named `@inner_block`, to render
HEEx content via the `render_slot/1` function.

If the values rendered in the slot need to be dynamic, you can pass a second value back to the
HEEx content by calling `render_slot/2`:

    slot :inner_block, required: true

    attr :entries, :list, default: []

    def unordered_list(assigns) do
      ~H"""
       
         {render_slot(@inner_block, entry)} 
       
      """
    end

When invoking the function component, you can use the special attribute `:let` to take the value
that the function component passes back and bind it to a variable:

```heex
<.unordered_list :let={fruit} entries={~w(apples bananas cherries)}>
  I like  {fruit} !
</.unordered_list>
```

Rendering the following HTML:

```html
 
   I like  apples ! 
   I like  bananas ! 
   I like  cherries ! 
 
```

Now the separation of concerns is maintained: the caller can specify multiple values in a list
attribute without having to specify the HEEx content that surrounds and separates them.

### Named slots - Phoenix.Component (module)

In addition to the default slot, function components can accept multiple, named slots of HEEx
content. For example, imagine you want to create a modal that has a header, body, and footer:

    slot :header
    slot :inner_block, required: true
    slot :footer, required: true

    def modal(assigns) do
      ~H"""
       
         
          {render_slot(@header) || "Modal"}
         
         
          {render_slot(@inner_block)}
         
         
          {render_slot(@footer)}
         
       
      """
    end

You can invoke this function component using the named slot HEEx syntax:

```heex
<.modal>
  This is the body, everything not in a named slot is rendered in the default slot.
  <:footer>
    This is the bottom of the modal.
  </:footer>
</.modal>
```

Rendering the following HTML:

```html
 
   
    Modal.
   
   
    This is the body, everything not in a named slot is rendered in the default slot.
   
   
    This is the bottom of the modal.
   
 
```

As shown in the example above, `render_slot/1` returns `nil` when an optional slot
is declared and none is given. This can be used to attach default behaviour.

### Slot attributes - Phoenix.Component (module)

Unlike the default slot, it is possible to pass a named slot multiple pieces of HEEx content.
Named slots can also accept attributes, defined by passing a block to the `slot/3` macro.
If multiple pieces of content are passed, `render_slot/2` will merge and render all the values.

Below is a table component illustrating multiple named slots with attributes:

    slot :column, doc: "Columns with column labels" do
      attr :label, :string, required: true, doc: "Column label"
    end

    attr :rows, :list, default: []

    def table(assigns) do
      ~H"""
       
         
           {col.label} 
         
         
           {render_slot(col, row)} 
         
       
      """
    end

You can invoke this function component like so:

```heex
<.table rows={[%{name: "Jane", age: "34"}, %{name: "Bob", age: "51"}]}>
  <:column :let={user} label="Name">
    {user.name}
  </:column>
  <:column :let={user} label="Age">
    {user.age}
  </:column>
</.table>
```

Rendering the following HTML:

```html
 
   
     Name 
     Age 
   
   
     Jane 
     34 
   
   
     Bob 
     51 
   
 
```

You can learn more about slots and the `slot/3` macro [in its documentation](`slot/3`).

### Embedding external template files - Phoenix.Component (module)

The `embed_templates/1` macro can be used to embed `.html.heex` files
as function components. The directory path is based on the current
module (`__DIR__`), and a wildcard pattern may be used to select all
files within a directory tree. For example, imagine a directory listing:

```plain
├── components.ex
├── cards
│   ├── pricing_card.html.heex
│   └── features_card.html.heex
```

Then you can embed the page templates in your `components.ex` module
and call them like any other function component:

    defmodule MyAppWeb.Components do
      use Phoenix.Component

      embed_templates "cards/*"

      def landing_hero(assigns) do
        ~H"""
        <.pricing_card />
        <.features_card />
        """
      end
    end

See `embed_templates/1` for more information, including declarative
assigns support for embedded templates.

### Debug information - Phoenix.Component (module)

HEEx templates support adding annotations and locations to the rendered
page, which are special HTML comments and attributes that help you identify
where markup in your HTML document is rendered within your function component
tree.

For example, imagine the following HEEx template:

```heex
<.header>
  <.button>Click</.button>
</.header>
```

By turning on `debug_heex_annotations`, the HTML document would receive the
following comments when debug annotations are enabled:

```html
<!-- @caller lib/app_web/home_live.ex:20 -->
<!--   lib/app_web/core_components.ex:123 -->
 
  <!-- @caller lib/app_web/home_live.ex:48 -->
  <!--   lib/app_web/core_components.ex:456 -->
   Click 
  <!--   -->
 
<!--   -->
```

Similarly, you can also turn on `:debug_attributes`, which adds a
`data-phx-loc` attribute with the line of where each HTML tag is defined
(as well as `data-phx-pid` to the LiveView container):

```html
 
   Click 
 
```

These features work on any `~H` or `.html.heex` template. They can be enabled
globally with the following configuration in your `config/dev.exs` file:

    config :phoenix_live_view,
      debug_heex_annotations: true,
      debug_attributes: true

Changing this configuration will require `mix clean` and a full recompile.

### Dynamic Component Rendering - Phoenix.Component (module)

Sometimes you might need to decide at runtime which component to render.
Because function components are just regular functions, we can leverage
Elixir's `apply/3` function to dynamically call a module and/or function passed
in as an assign.

For example, using the following function component definition:

```elixir
attr :module, :atom, required: true
attr :function, :atom, required: true
# any shared attributes
attr :shared, :string, required: true

# any shared slots
slot :named_slot, required: true
slot :inner_block, required: true

def dynamic_component(assigns) do
  {mod, assigns} = Map.pop(assigns, :module)
  {func, assigns} = Map.pop(assigns, :function)

  apply(mod, func, [assigns])
end
```

Then you can use the `dynamic_component` function like so:

```heex
<.dynamic_component
  module={MyAppWeb.MyModule}
  function={:my_function}
  shared="Yay Elixir!"
>
   Howdy from the inner block! 
  <:named_slot>
     Howdy from the named slot! 
  </:named_slot>
</.dynamic_component>
```

This will call the `MyAppWeb.MyModule.my_function/1` function passing in the remaining assigns.

```elixir
defmodule MyAppWeb.MyModule do
  attr :shared, :string, required: true

  slot :named_slot, required: true
  slot :inner_block, required: true

  def my_function(assigns) do
    ~H"""
     Dynamic component with shared assigns: {@shared} 
    {render_slot(@inner_block)}
    {render_slot(@named_slot)}
    """
  end
end
```

Resulting in the following HTML:

```html
 Dynamic component with shared assigns: Yay Elixir! 
 Howdy from the inner block! 
 Howdy from the named slot! 
```

Note that to get the most out of `Phoenix.Component`'s compile-time validations, it is beneficial to
define such a `dynamic_component` for a specific set of components sharing the same API, instead of
defining it for the general case.
In this example, we defined our `dynamic_component` to expect an assign called `shared`, as well as
two slots that all components we want to use with it must implement.
The called `my_function` component's attribute and slot definitions cannot be validated through the apply call.

### Phoenix.Component.assign/2 (function)

Adds key-value pairs to assigns.

The first argument is either a LiveView `socket` or an `assigns` map from function components.

A keyword list or a map of assigns must be given as argument to be merged into existing assigns.

### Examples - Phoenix.Component.assign/2 (function)

iex> assign(socket, name: "Elixir", logo: "💧")
    iex> assign(socket, %{name: "Elixir"})

### Phoenix.Component.assign/3 (function)

Adds a `key`-`value` pair to `socket_or_assigns`.

The first argument is either a LiveView `socket` or an `assigns` map from function components.

### Examples - Phoenix.Component.assign/3 (function)

iex> assign(socket, :name, "Elixir")

### Phoenix.Component.assign_new/3 (function)

Assigns the given `key` with value from `fun` into `socket_or_assigns` if one does not yet exist.

The first argument is either a LiveView `socket` or an `assigns` map from function components.

This function is useful for lazily assigning values and sharing assigns.
We will cover both use cases next.

### Lazy assigns - Phoenix.Component.assign_new/3 (function)

Imagine you have a function component that accepts a color:

```heex
<.my_component bg_color="red" />
```

The color is also optional, so you can skip it:

```heex
<.my_component />
```

In such cases, the implementation can use `assign_new` to lazily
assign a color if none is given. Let's make it so it picks a random one
when none is given:

    def my_component(assigns) do
      assigns = assign_new(assigns, :bg_color, fn -> Enum.random(~w(bg-red-200 bg-green-200 bg-blue-200)) end)

      ~H"""
       
        Example
       
      """
    end

### Sharing assigns - Phoenix.Component.assign_new/3 (function)

It is possible to share assigns between the Plug pipeline and LiveView on disconnected render
and between parent-child LiveViews when connected.

### When disconnected - Phoenix.Component.assign_new/3 (function)

When a user first accesses an application using LiveView, the LiveView is first rendered in its
disconnected state, as part of a regular HTML response. By using `assign_new` in the mount
callback of your LiveView, you can instruct LiveView to re-use any assigns already set in `conn`
during disconnected state.

Imagine you have a Plug that does:

    # A plug
    def authenticate(conn, _opts) do
      if user_id = get_session(conn, :user_id) do
        assign(conn, :current_user, Accounts.get_user!(user_id))
      else
        send_resp(conn, :forbidden)
      end
    end

You can re-use the `:current_user` assign in your LiveView during the initial render:

    def mount(_params, %{"user_id" => user_id}, socket) do
      {:ok, assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)}
    end

In such case `conn.assigns.current_user` will be used if present. If there is no such
`:current_user` assign or the LiveView was mounted as part of the live navigation, where no Plug
pipelines are invoked, then the anonymous function is invoked to execute the query instead.

### When connected - Phoenix.Component.assign_new/3 (function)

LiveView is also able to share assigns via `assign_new` with children LiveViews,
as long as the child LiveView is also mounted when the parent LiveView is mounted
and the child LiveView is not rendered with `sticky: true`. Let's see an example.

If the parent LiveView defines a `:current_user` assign and the child LiveView also
uses `assign_new/3` to fetch the `:current_user` in its `mount/3` callback, as in
the previous subsection, the assign will be fetched from the parent LiveView, once
again avoiding additional database queries.

Note that `fun` also provides access to the previously assigned values:

    assigns =
      assigns
      |> assign_new(:foo, fn -> "foo" end)
      |> assign_new(:bar, fn %{foo: foo} -> foo <> "bar" end)

Assigns sharing is performed when possible but not guaranteed. Therefore, you must
ensure the result of the function given to `assign_new/3` is the same as if the value
was fetched from the parent. Otherwise consider passing values to the child LiveView
as part of its session.

### Phoenix.Component.assigns_to_attributes/2 (function)

Filters the assigns as a list of keywords for use in dynamic tag attributes.

One should prefer to use declarative assigns and `:global` attributes
over this function.

### Examples - Phoenix.Component.assigns_to_attributes/2 (function)

Imagine the following `my_link` component which allows a caller
to pass a `new_window` assign, along with any other attributes they
would like to add to the element, such as class, data attributes, etc:

```heex
<.my_link to="/" id={@id} new_window={true} class="my-class">Home</.my_link>
```

We could support the dynamic attributes with the following component:

    def my_link(assigns) do
      target = if assigns[:new_window], do: "_blank", else: false
      extra = assigns_to_attributes(assigns, [:new_window, :to])

      assigns =
        assigns
        |> assign(:target, target)
        |> assign(:extra, extra)

      ~H"""
       
        {render_slot(@inner_block)}
       
      """
    end

The above would result in the following rendered HTML:

```heex
 Home 
```

The second argument (optional) to `assigns_to_attributes` is a list of keys to
exclude. It typically includes reserved keys by the component itself, which either
do not belong in the markup, or are already handled explicitly by the component.

### Phoenix.Component.async_result/1 (function)

Renders a `Phoenix.LiveView.AsyncResult` struct (e.g. from `Phoenix.LiveView.assign_async/4`)
with slots for the different loading states.
The result state takes precedence over subsequent loading and failed
states.

> #### Note {: .info}
>
> The inner block receives the result of the async assign as a `:let`.
> The let is only accessible to the inner block and is not in scope to the
> other slots.

### Examples - Phoenix.Component.async_result/1 (function)

```elixir
def mount(%{"slug" => slug}, _, socket) do
  {:ok,
    socket
    |> assign_async(:org, fn -> {:ok, %{org: fetch_org!(slug)}} end)}
end
```

```heex
<.async_result :let={org} assign={@org}>
  <:loading>Loading organization...</:loading>
  <:failed :let={_failure}>there was an error loading the organization</:failed>
  <%= if org do %>
    {org.name}
  <% else %>
    You don't have an organization yet.
  <% end %>
</.async_result>
```

See [Async Operations](`m:Phoenix.LiveView#module-async-operations`) for more information.

To display loading and failed states again on subsequent `assign_async` calls,
reset the assign to a result-free `%AsyncResult{}`:

```elixir
{:noreply,
  socket
  |> assign_async(:page, :data, &reload_data/0)
  |> assign(:page, AsyncResult.loading())}
```

### Attributes - Phoenix.Component.async_result/1 (function)

* `assign` (`Phoenix.LiveView.AsyncResult`) (required)

### Slots - Phoenix.Component.async_result/1 (function)

* `loading` - rendered while the assign is loading for the first time.
* `failed` - rendered when an error or exit is caught or assign_async returns `{:error, reason}` for the first time. Receives the error as a `:let`.
* `inner_block` - rendered when the assign is loaded successfully via `AsyncResult.ok/2`. Receives the result as a `:let`.

### Phoenix.Component.attr/3 (macro)

Declares attributes for a HEEx function components.

### Arguments - Phoenix.Component.attr/3 (macro)

* `name` - an atom defining the name of the attribute. Note that attributes cannot define the
same name as any other attributes or slots declared for the same component.

* `type` - an atom defining the type of the attribute.

* `opts` - a keyword list of options. Defaults to `[]`.

### Types - Phoenix.Component.attr/3 (macro)

An attribute is declared by its name, type, and options. The following types are supported:

| Name            | Description                                                          |
|-----------------|----------------------------------------------------------------------|
| `:any`          | any term (including `nil`)                                           |
| `:string`       | any binary string                                                    |
| `:atom`         | any atom (including `true`, `false`, and `nil`)                      |
| `:boolean`      | any boolean                                                          |
| `:integer`      | any integer                                                          |
| `:float`        | any float                                                            |
| `:list`         | any list of any arbitrary types                                      |
| `:map`          | any map of any arbitrary types                                       |
| `:fun`          | any function                                                         |
| `{:fun, arity}` | any function of arity                                                |
| `:global`       | any common HTML attributes, plus those defined by `:global_prefixes` |
| A struct module | any module that defines a struct with `defstruct/1`                  |

Note only `:any` and `:atom` expect the value to be set to `nil`.

### Options - Phoenix.Component.attr/3 (macro)

* `:required` - marks an attribute as required. If a caller does not pass the given attribute,
a compile warning is issued.

* `:default` - the default value for the attribute if not provided. If this option is
  not set and the attribute is not given, accessing the attribute will fail unless a
  value is explicitly set with `assign_new/3`.

* `:examples` - a non-exhaustive list of values accepted by the attribute, used for documentation
  purposes.

* `:values` - an exhaustive list of values accepted by the attributes. If a caller passes a literal
  not contained in this list, a compile warning is issued.

* `:doc` - documentation for the attribute.

### Compile-Time Validations - Phoenix.Component.attr/3 (macro)

LiveView performs some validation of attributes via the `:phoenix_live_view` compiler.
When attributes are defined, LiveView will warn at compilation time on the caller if:

* A required attribute of a component is missing.

* An unknown attribute is given.

* You specify a literal attribute (such as `value="string"` or `value`, but not `value={expr}`)
and the type does not match. The following types currently support literal validation:
`:string`, `:atom`, `:boolean`, `:integer`, `:float`, `:map` and `:list`.

* You specify a literal attribute and it is not a member of the `:values` list.

LiveView does not perform any validation at runtime. This means the type information is mostly
used for documentation and reflection purposes.

On the side of the LiveView component itself, defining attributes provides the following quality
of life improvements:

* The default value of all attributes will be added to the `assigns` map upfront.

* Attribute documentation is generated for the component.

* Required struct types are annotated and emit compilation warnings. For example, if you specify
`attr :user, User, required: true` and then you write `@user.non_valid_field` in your template,
a warning will be emitted.

* Calls made to the component are tracked for reflection and validation purposes.

### Documentation Generation - Phoenix.Component.attr/3 (macro)

Public function components that define attributes will have their attribute
types and docs injected into the function's documentation, depending on the
value of the `@doc` module attribute:

* if `@doc` is a string, the attribute docs are injected into that string. The optional
placeholder `[INSERT LVATTRDOCS]` can be used to specify where in the string the docs are
injected. Otherwise, the docs are appended to the end of the `@doc` string.

* if `@doc` is unspecified, the attribute docs are used as the default `@doc` string.

* if `@doc` is `false`, the attribute docs are omitted entirely.

The injected attribute docs are formatted as a markdown list:

  * `name` (`:type`) (required) - attr docs. Defaults to `:default`.

By default, all attributes will have their types and docs injected into the function `@doc`
string. To hide a specific attribute, you can set the value of `:doc` to `false`.

### Example - Phoenix.Component.attr/3 (macro)

attr :name, :string, required: true
    attr :age, :integer, required: true

    def celebrate(assigns) do
      ~H"""
       
        Happy birthday {@name}!
        You are {@age} years old.
       
      """
    end

### Phoenix.Component.changed?/2 (function)

Checks if the given key changed in `socket_or_assigns`.

The first argument is either a LiveView `socket` or an `assigns` map from function components.

### Examples - Phoenix.Component.changed?/2 (function)

iex> changed?(socket, :count)

### Phoenix.Component.dynamic_tag/1 (function)

Generates a dynamically named HTML tag.

Raises an `ArgumentError` if the tag name is found to be unsafe HTML.

### Attributes - Phoenix.Component.dynamic_tag/1 (function)

* `tag_name` (`:string`) (required) - The name of the tag, such as `div`.
* `name` (`:string`) - Deprecated: use tag_name instead. If tag_name is used, passed to the tag. Otherwise the name of the tag, such as `div`.
* Global attributes are accepted. Additional HTML attributes to add to the tag, ensuring proper escaping.

### Slots - Phoenix.Component.dynamic_tag/1 (function)

* `inner_block`

### Examples - Phoenix.Component.dynamic_tag/1 (function)

```heex
<.dynamic_tag tag_name="input" name="my-input" type="text"/>
```

```html
 
```

```heex
<.dynamic_tag tag_name="p">content</.dynamic_tag>
```

```html
 content 
```

### Phoenix.Component.embed_templates/2 (macro)

Embeds external template files into the module as function components.

### Options - Phoenix.Component.embed_templates/2 (macro)

* `:root` - The root directory to embed files. Defaults to the current
    module's directory (`__DIR__`)
  * `:suffix` - A string value to append to embedded function names. By
    default, function names will be the name of the template file excluding
    the format and engine.

A wildcard pattern may be used to select all files within a directory tree.
For example, imagine a directory listing:

```plain
├── components.ex
├── pages
│   ├── about_page.html.heex
│   └── welcome_page.html.heex
```

Then to embed the page templates in your `components.ex` module:

    defmodule MyAppWeb.Components do
      use Phoenix.Component

      embed_templates "pages/*"
    end

Now, your module will have an `about_page/1` and `welcome_page/1` function
component defined. Embedded templates also support declarative assigns
via bodyless function definitions, for example:

    defmodule MyAppWeb.Components do
      use Phoenix.Component

      embed_templates "pages/*"

      attr :name, :string, required: true
      def welcome_page(assigns)

      slot :header
      def about_page(assigns)
    end

Multiple invocations of `embed_templates` is also supported, which can be
useful if you have more than one template format. For example:

    defmodule MyAppWeb.Emails do
      use Phoenix.Component

      embed_templates "emails/*.html", suffix: "_html"
      embed_templates "emails/*.text", suffix: "_text"
    end

Note: this function is the same as `Phoenix.Template.embed_templates/2`.
It is also provided here for convenience and documentation purposes.
Therefore, if you want to embed templates for other formats, which are
not related to `Phoenix.Component`, prefer to
`import Phoenix.Template, only: [embed_templates: 1]` than this module.

### Phoenix.Component.focus_wrap/1 (function)

Wraps tab focus around a container for accessibility.

This is an essential accessibility feature for interfaces such as modals, dialogs, and menus.

### Attributes - Phoenix.Component.focus_wrap/1 (function)

* `id` (`:string`) (required) - The DOM identifier of the container tag.
* Global attributes are accepted. Additional HTML attributes to add to the container tag.

### Slots - Phoenix.Component.focus_wrap/1 (function)

* `inner_block` (required) - The content rendered inside of the container tag.

### Examples - Phoenix.Component.focus_wrap/1 (function)

Simply render your inner content within this component and focus will be wrapped around the
container as the user tabs through the containers content:

```heex
<.focus_wrap id="my-modal" class="bg-white">
   
    Are you sure?
     Cancel 
     OK 
   
</.focus_wrap>
```

### Phoenix.Component.form/1 (function)

Renders a form.

This function receives a `Phoenix.HTML.Form` struct, generally created with
`to_form/2`, and generates the relevant form tags. It can be used either
inside LiveView or outside.

> To see how forms work in practice, you can run
> `mix phx.gen.live Blog Post posts title body:text` inside your Phoenix
> application, which will setup the necessary database tables and LiveViews
> to manage your data.

### Examples: inside LiveView - Phoenix.Component.form/1 (function)

Inside LiveViews, this function component is typically called with
as `for={@form}`, where `@form` is the result of the `to_form/1` function.
`to_form/1` expects either a map or an [`Ecto.Changeset`](https://hexdocs.pm/ecto/Ecto.Changeset.html)
as the source of data and normalizes it into `Phoenix.HTML.Form` structure.

For example, you may use the parameters received in a
`c:Phoenix.LiveView.handle_event/3` callback to create an Ecto changeset
and then use `to_form/1` to convert it to a form. Then, in your templates,
you pass the `@form` as argument to `:for`:

```heex
<.form
  for={@form}
  phx-change="change_name"
>
  <.input field={@form[:email]} />
</.form>
```

The `.input` component is generally defined as part of your own application
and adds all styling necessary:

```heex
def input(assigns) do
  ~H"""
   
  """
end
```

A form accepts multiple options. For example, if you are doing file uploads
and you want to capture submissions, you might write instead:

```heex
<.form
  for={@form}
  multipart
  phx-change="change_user"
  phx-submit="save_user"
>
  ...
   
</.form>
```

Notice how both examples use `phx-change`. The LiveView must implement the
`phx-change` event and store the input values as they arrive on change.
This is important because, if an unrelated change happens on the page,
LiveView should re-render the inputs with their updated values. Without `phx-change`,
the inputs would otherwise be cleared. Alternatively, you can use `phx-update="ignore"`
on the form to discard any updates.

### Using the for attribute - Phoenix.Component.form/1 (function)

The `for` attribute can also be a map or an Ecto.Changeset. In such cases,
a form will be created on the fly, and you can capture it using `:let`:

```heex
<.form
  :let={form}
  for={@changeset}
  phx-change="change_user"
>
```

However, such approach is discouraged in LiveView for two reasons:

  * LiveView can better optimize your code if you access the form fields
    using `@form[:field]` rather than through the let-variable `form`

  * Ecto changesets are meant to be single use. By never storing the changeset
    in the assign, you will be less tempted to use it across operations

### A note on :errors - Phoenix.Component.form/1 (function)

Even if `changeset.errors` is non-empty, errors will not be displayed in a
form if [the changeset
`:action`](https://hexdocs.pm/ecto/Ecto.Changeset.html#module-changeset-actions)
is `nil` or `:ignore`.

This is useful for things like validation hints on form fields, e.g. an empty
changeset for a new form. That changeset isn't valid, but we don't want to
show errors until an actual user action has been performed.

For example, if the user submits and a `Repo.insert/1` is called and fails on
changeset validation, the action will be set to `:insert` to show that an
insert was attempted, and the presence of that action will cause errors to be
displayed. The same is true for Repo.update/delete.

Error visibility is handled by providing the action to `to_form/2`, which will
set the underlying changeset action. You can also set the action manually by
directly updating on the `Ecto.Changeset` struct field, or by using
`Ecto.Changeset.apply_action/2`. Since the action can be arbitrary, you can
set it to `:validate` or anything else to avoid giving the impression that a
database operation has actually been attempted.

### Displaying errors on used and unused input fields - Phoenix.Component.form/1 (function)

Used inputs are only those inputs that have been focused, interacted with, or
submitted by the client. In most cases, a user shouldn't receive error feedback
for forms they haven't yet interacted with, until they submit the form. Filtering
the errors based on used input fields can be done with `used_input?/1`.

### Example: outside LiveView (regular HTTP requests) - Phoenix.Component.form/1 (function)

The `form` component can still be used to submit forms outside of LiveView.
In such cases, the standard HTML `action` attribute MUST be given.
Without said attribute, the `form` method and csrf token are discarded.

```heex
<.form :let={f} for={@changeset} action={~p"/comments/#{@comment}"}>
  <.input field={f[:body]} />
</.form>
```

In the example above, we passed a changeset to `for` and captured
the value using `:let={f}`. This approach is ok outside of LiveViews,
as there are no change tracking optimizations to consider.

### CSRF protection - Phoenix.Component.form/1 (function)

CSRF protection is a mechanism to ensure that the user who rendered
the form is the one actually submitting it. This module generates a
CSRF token by default. Your application should check this token on
the server to avoid attackers from making requests on your server on
behalf of other users. Phoenix by default checks this token.

When posting a form with a host in its address, such as "//host.com/path"
instead of only "/path", Phoenix will include the host signature in the
token and validate the token only if the accessed host is the same as
the host in the token. This is to avoid tokens from leaking to third
party applications. If this behaviour is problematic, you can generate
a non-host specific token with `Plug.CSRFProtection.get_csrf_token/0` and
pass it to the form generator via the `:csrf_token` option.

### Attributes - Phoenix.Component.form/1 (function)

* `for` (`:any`) (required) - An existing form or the form source data.
* `action` (`:string`) - The action to submit the form on.
  This attribute must be given if you intend to submit the form to a URL without LiveView.

* `as` (`:atom`) - The prefix to be used in names and IDs generated by the form.
  For example, setting `as: :user_params` means the parameters
  will be nested "user_params" in your `handle_event` or
  `conn.params["user_params"]` for regular HTTP requests.
  If you set this option, you must capture the form with `:let`.

* `csrf_token` (`:any`) - A token to authenticate the validity of requests.
  One is automatically generated when an action is given and the method is not `get`.
  When set to `false`, no token is generated.

* `errors` (`:list`) - Use this to manually pass a keyword list of errors to the form.
  This option is useful when a regular map is given as the form
  source and it will make the errors available under `f.errors`.
  If you set this option, you must capture the form with `:let`.

* `method` (`:string`) - The HTTP method.
  It is only used if an `:action` is given. If the method is not `get` nor `post`,
  an input tag with name `_method` is generated alongside the form tag.
  If an `:action` is given with no method, the method will default to the return value
  of `Phoenix.HTML.FormData.to_form/2` (usually `post`).

* `multipart` (`:boolean`) - Sets `enctype` to `multipart/form-data`.
  Required when uploading files.

  Defaults to `false`.
* Global attributes are accepted. Additional HTML attributes to add to the form tag. Supports all globals plus: `["autocomplete", "name", "rel", "enctype", "novalidate", "target"]`.

### Slots - Phoenix.Component.form/1 (function)

* `inner_block` (required) - The content rendered inside of the form tag.

### Phoenix.Component.inputs_for/1 (function)

Renders nested form inputs for associations or embeds.

### Attributes - Phoenix.Component.inputs_for/1 (function)

* `field` (`Phoenix.HTML.FormField`) (required) - A %Phoenix.HTML.Form{}/field name tuple, for example: {@form[:email]}.
* `id` (`:string`) - The id base to be used in the form inputs. Defaults to the parent form id. The computed
  id will be the concatenation of the base id with the field name, along with a book keeping
  index for each input in the list.

* `as` (`:atom`) - The name to be used in the form, defaults to the concatenation of the given
  field to the parent form name.

* `default` (`:any`) - The value to use if none is available.
* `prepend` (`:list`) - The values to prepend when rendering. This only applies if the field value
  is a list and no parameters were sent through the form.

* `append` (`:list`) - The values to append when rendering. This only applies if the field value
  is a list and no parameters were sent through the form.

* `skip_hidden` (`:boolean`) - Skip the automatic rendering of hidden fields to allow for more tight control
  over the generated markup.

  Defaults to `false`.
* `skip_persistent_id` (`:boolean`) - Skip the automatic rendering of hidden _persistent_id fields used for reordering
  inputs.

  Defaults to `false`.
* `options` (`:list`) - Any additional options for the `Phoenix.HTML.FormData` protocol
  implementation.

  Defaults to `[]`.

### Slots - Phoenix.Component.inputs_for/1 (function)

* `inner_block` (required) - The content rendered for each nested form.

### Examples - Phoenix.Component.inputs_for/1 (function)

```heex
<.form
  for={@form}
  phx-change="change_name"
>
  <.inputs_for :let={f_nested} field={@form[:nested]}>
    <.input type="text" field={f_nested[:name]} />
  </.inputs_for>
</.form>
```

### Dynamically adding and removing inputs - Phoenix.Component.inputs_for/1 (function)

Dynamically adding and removing inputs is supported by rendering named buttons for
inserts and removals. Like inputs, buttons with name/value pairs are serialized with
form data on change and submit events. Libraries such as Ecto, or custom param
filtering can then inspect the parameters and handle the added or removed fields.
This can be combined with `Ecto.Changeset.cast_assoc/3`'s `:sort_param` and `:drop_param`
options. For example, imagine a parent with an `:emails` `has_many` or `embeds_many`
association. To cast the user input from a nested form, one simply needs to configure
the options:

    schema "mailing_lists" do
      field :title, :string

      embeds_many :emails, EmailNotification, on_replace: :delete do
        field :email, :string
        field :name, :string
      end
    end

    def changeset(list, attrs) do
      list
      |> cast(attrs, [:title])
      |> cast_embed(:emails,
        with: &email_changeset/2,
        sort_param: :emails_sort,
        drop_param: :emails_drop
      )
    end

Here we see the `:sort_param` and `:drop_param` options in action.

> Note: `on_replace: :delete` on the `has_many` and `embeds_many` is required
> when using these options.

When Ecto sees the specified sort or drop parameter from the form, it will sort
the children based on the order they appear in the form, add new children it hasn't
seen, or drop children if the parameter instructs it to do so.

The markup for such a schema and association would look like this:

```heex
<.inputs_for :let={ef} field={@form[:emails]}>
   
  <.input type="text" field={ef[:email]} placeholder="email" />
  <.input type="text" field={ef[:name]} placeholder="name" />
   
    <.icon name="hero-x-mark" class="w-6 h-6 relative top-2" />
   
</.inputs_for>

 

 
  add more
 
```

We used `inputs_for` to render inputs for the `:emails` association, which
contains an email address and name input for each child. Within the nested inputs,
we render a hidden `mailing_list[emails_sort][]` input, which is set to the index of the
given child. This tells Ecto's cast operation how to sort existing children, or
where to insert new children. Next, we render the email and name inputs as usual.
Then we render a button containing the "delete" text with the name `mailing_list[emails_drop][]`,
containing the index of the child as its value.

Like before, this tells Ecto to delete the child at this index when the button is
clicked. We use `phx-click={JS.dispatch("change")}` on the button to tell LiveView
to treat this button click as a change event, rather than a submit event on the form,
which invokes our form's `phx-change` binding.

Outside the `inputs_for`, we render an empty `mailing_list[emails_drop][]` input,
to ensure that all children are deleted when saving a form where the user
dropped all entries. This hidden input is required whenever dropping associations.

Finally, we also render another button with the sort param name `mailing_list[emails_sort][]`
and `value="new"` name with accompanied "add more" text. Please note that this button must
have `type="button"` to prevent it from submitting the form.
Ecto will treat unknown sort params as new children and build a new child.
This button is optional and only necessary if you want to dynamically add entries.
You can optionally add a similar button before the `<.inputs_for>`, in the case you want
to prepend entries.

>

### A note on accessing a field's value - Phoenix.Component.inputs_for/1 (function)

>
> You may be tempted to access `form[:field].value` or attempt to manipulate
> the form metadata in your templates. However, bear in mind that the `form[:field]`
> value reflects the most recent changes. For example, an `:integer` field may
> either contain integer values, but it may also hold a string, if the form has
> been submitted.
>
> This is particularly noticeable when using `inputs_for`. Accessing the `.value`
> of a nested field may either return a struct, a changeset, or raw parameters
> sent by the client (when using `drop_param`). This makes the `form[:field].value`
> impractical for deriving or computing other properties.
>
> The correct way to approach this problem is by computing any property either in
> your LiveViews, by traversing the relevant changesets and data structures, or by
> moving the logic to the `Ecto.Changeset` itself.
>
> As an example, imagine you are building a time tracking application where:
>
> - users enter the total work time for a day
> - individual activities are tracked as embeds
> - the sum of all activities should match the total time
> - the form should display the remaining time
>
> Instead of trying to calculate the remaining time in your template by
> doing something like `calculate_remaining(@form)` and accessing
> `form[:activities].value`, calculate the remaining time based
> on the changeset in your `handle_event` instead:
>
> ```elixir
> def handle_event("validate", %{"tracked_day" => params}, socket) do
>   changeset = TrackedDay.changeset(socket.assigns.tracked_day, params)
>   remaining = calculate_remaining(changeset)
>   {:noreply, assign(socket, form: to_form(changeset, action: :validate), remaining: remaining)}
> end
>
> # Helper function to calculate remaining time
> defp calculate_remaining(changeset) do
>   total = Ecto.Changeset.get_field(changeset, :total)
>   activities = Ecto.Changeset.get_embed(changeset, :activities)
>
>   Enum.reduce(activities, total, fn activity, acc ->
>     duration =
>       case activity do
>         %{valid?: true} = changeset -> Ecto.Changeset.get_field(changeset, :duration)
>         # if the activity is invalid, we don't include its duration in the calculation
>         _ -> 0
>       end
>
>     acc - length
>   end)
> end
> ```
>
> This logic might also be implemented directly in your schema module and, if you
> often need the `:remaining` value, you could also add it as a `:virtual` field to
> your schema and run the calculation when validating the changeset:
>
> ```elixir
> def changeset(tracked_day, attrs) do
>   tracked_day
>   |> cast(attrs, [:total_duration])
>   |> cast_embed(:activities)
>   |> validate_required([:total_duration])
>   |> validate_number(:total_duration, greater_than: 0)
>   |> validate_and_put_remaining_time()
> end
>
> defp validate_and_put_remaining_time(changeset) do
>   remaining = calculate_remaining(changeset)
>   put_change(changeset, :remaining, remaining)
> end
> ```
>
> By using this approach, you can safely render the remaining time in your template
> using `@form[:remaining].value`, avoiding the pitfalls of directly accessing complex field values.

### Phoenix.Component.intersperse/1 (function)

Intersperses separator slot between an enumerable.

Useful when you need to add a separator between items such as when
rendering breadcrumbs for navigation. Provides each item to the
inner block.

### Examples - Phoenix.Component.intersperse/1 (function)

```heex
<.intersperse :let={item} enum={["home", "profile", "settings"]}>
  <:separator>
     | 
  </:separator>
  {item}
</.intersperse>
```

Renders the following markup:

```html
home  |  profile  |  settings
```

### Attributes - Phoenix.Component.intersperse/1 (function)

* `enum` (`:any`) (required) - the enumerable to intersperse with separators.

### Slots - Phoenix.Component.intersperse/1 (function)

* `inner_block` (required) - the inner_block to render for each item.
* `separator` (required) - the slot for the separator.

### Phoenix.Component.link/1 (function)

Generates a link to a given route.

It is typically used with one of the three attributes:

  * `patch` - on click, it patches the current LiveView with the given path
  * `navigate` - on click, it navigates to a new LiveView at the given path
  * `href` - on click, it performs traditional browser navigation (as any ` ` tag)

### Attributes - Phoenix.Component.link/1 (function)

* `navigate` (`:string`) - Navigates to a LiveView.
  When redirecting across LiveViews, the browser page is kept, but a new LiveView process
  is mounted and its contents is loaded on the page. It is only possible to navigate
  between LiveViews declared under the same router
  [`live_session`](`Phoenix.LiveView.Router.live_session/3`).
  When used outside of a LiveView or across live sessions, it behaves like a regular
  browser redirect.

* `patch` (`:string`) - Patches the current LiveView.
  The `handle_params` callback of the current LiveView will be invoked and the minimum content
  will be sent over the wire, as any other LiveView diff.

* `href` (`:any`) - Uses traditional browser navigation to the new location.
  This means the whole page is reloaded on the browser.

* `replace` (`:boolean`) - When using `:patch` or `:navigate`,
  should the browser's history be replaced with `pushState`?

  Defaults to `false`.
* `method` (`:string`) - The HTTP method to use with the link. This is intended for usage outside of LiveView
  and therefore only works with the `href={...}` attribute. It has no effect on `patch`
  and `navigate` instructions.

  In case the method is not `get`, the link is generated inside the form which sets the proper
  information. In order to submit the form, JavaScript must be enabled in the browser.

  Defaults to `"get"`.
* `csrf_token` (`:any`) - A boolean or custom token to use for links with an HTTP method other than `get`. Defaults to `true`.
* Global attributes are accepted. Additional HTML attributes added to the `a` tag. Supports all globals plus: `["download", "hreflang", "referrerpolicy", "rel", "target", "type"]`.

### Slots - Phoenix.Component.link/1 (function)

* `inner_block` (required) - The content rendered inside of the `a` tag.

### Examples - Phoenix.Component.link/1 (function)

```heex
<.link href="/">Regular anchor link</.link>
```

```heex
<.link navigate={~p"/"} class="underline">home</.link>
```

```heex
<.link navigate={~p"/?sort=asc"} replace={false}>
  Sort By Price
</.link>
```

```heex
<.link patch={~p"/details"}>view details</.link>
```

```heex
<.link href={URI.parse("https://elixir-lang.org")}>hello</.link>
```

```heex
<.link href="/the_world" method="delete" data-confirm="Really?">delete</.link>
```

### JavaScript dependency - Phoenix.Component.link/1 (function)

In order to support links where `:method` is not `"get"` or use the above data attributes,
`Phoenix.HTML` relies on JavaScript. You can load `priv/static/phoenix_html.js` into your
build tool.

### Data attributes - Phoenix.Component.link/1 (function)

Data attributes are added as a keyword list passed to the `data` key. The following data
attributes are supported:

* `data-confirm` - shows a confirmation prompt before generating and submitting the form when
`:method` is not `"get"`.

### Overriding the default confirm behaviour - Phoenix.Component.link/1 (function)

`phoenix_html.js` does trigger a custom event `phoenix.link.click` on the clicked DOM element
when a click happened. This allows you to intercept the event on its way bubbling up
to `window` and do your own custom logic to enhance or replace how the `data-confirm`
attribute is handled. You could for example replace the browsers `confirm()` behavior with
a custom javascript implementation:

```javascript
// Compared to a javascript window.confirm, the custom dialog does not block
// javascript execution. Therefore to make this work as expected we store
// the successful confirmation as an attribute and re-trigger the click event.
// On the second click, the `data-confirm-resolved` attribute is set and we proceed.
const RESOLVED_ATTRIBUTE = "data-confirm-resolved";
// listen on document.body, so it's executed before the default of
// phoenix_html, which is listening on the window object
document.body.addEventListener('phoenix.link.click', function (e) {
  // Prevent default implementation
  e.stopPropagation();
  // Introduce alternative implementation
  var message = e.target.getAttribute("data-confirm");
  if(!message){ return; }

  // Confirm is resolved execute the click event
  if (e.target?.hasAttribute(RESOLVED_ATTRIBUTE)) {
    e.target.removeAttribute(RESOLVED_ATTRIBUTE);
    return;
  }

  // Confirm is needed, preventDefault and show your modal
  e.preventDefault();
  e.target?.setAttribute(RESOLVED_ATTRIBUTE, "");

  vex.dialog.confirm({
    message: message,
    callback: function (value) {
      if (value == true) {
        // Customer confirmed, re-trigger the click event.
        e.target?.click();
      } else {
        // Customer canceled
        e.target?.removeAttribute(RESOLVED_ATTRIBUTE);
      }
    }
  })
}, false);
```

Or you could attach your own custom behavior.

```javascript
window.addEventListener('phoenix.link.click', function (e) {
  // Introduce custom behaviour
  var message = e.target.getAttribute("data-prompt");
  var answer = e.target.getAttribute("data-prompt-answer");
  if(message && answer && (answer != window.prompt(message))) {
    e.preventDefault();
  }
}, false);
```

The latter could also be bound to any `click` event, but this way you can be sure your custom
code is only executed when the code of `phoenix_html.js` is run.

### CSRF Protection - Phoenix.Component.link/1 (function)

By default, CSRF tokens are generated through `Plug.CSRFProtection`.

### Phoenix.Component.live_component/1 (function)

A function component for rendering `Phoenix.LiveComponent` within a parent LiveView.

While LiveViews can be nested, each LiveView starts its own process. A LiveComponent provides
similar functionality to LiveView, except they run in the same process as the LiveView,
with its own encapsulated state. That's why they are called stateful components.

### Attributes - Phoenix.Component.live_component/1 (function)

* `id` (`:string`) (required) - A unique identifier for the LiveComponent. Note the `id` won't
necessarily be used as the DOM `id`. That is up to the component to decide.

* `module` (`:atom`) (required) - The LiveComponent module to render.

Any additional attributes provided will be passed to the LiveComponent as a map of assigns.
See `Phoenix.LiveComponent` for more information.

### Examples - Phoenix.Component.live_component/1 (function)

```heex
<.live_component module={MyApp.WeatherComponent} id="thermostat" city="Kraków" />
```

### Phoenix.Component.live_file_input/1 (function)

Builds a file input tag for a LiveView upload.

### Attributes - Phoenix.Component.live_file_input/1 (function)

* `upload` (`Phoenix.LiveView.UploadConfig`) (required) - The `Phoenix.LiveView.UploadConfig` struct.
* `accept` (`:string`) - the optional override for the accept attribute. Defaults to :accept specified by allow_upload.
* Global attributes are accepted. Supports all globals plus: `["webkitdirectory", "required", "disabled", "capture", "form"]`.

### Customizing the Label - Phoenix.Component.live_file_input/1 (function)

The `id` attribute cannot be overwritten, but you can create a label with a `for` attribute
pointing to the UploadConfig `ref`:

```heex
 
  <.live_file_input upload={@uploads.avatar} />
 
```

### Drag and Drop - Phoenix.Component.live_file_input/1 (function)

Drag and drop is supported by annotating the droppable container with a `phx-drop-target`
attribute pointing to the UploadConfig `ref`, so the following markup is all that is required
for drag and drop support:

```heex
 
  <.live_file_input upload={@uploads.avatar} />
 
```

### Examples - Phoenix.Component.live_file_input/1 (function)

Rendering a file input:

```heex
<.live_file_input upload={@uploads.avatar} />
```

Rendering a file input with a label:

```heex
 Avatar 
<.live_file_input upload={@uploads.avatar} />
```

### Phoenix.Component.live_flash/2 (function)

Returns the flash message from the LiveView flash assign.

### Examples - Phoenix.Component.live_flash/2 (function)

```heex
 {live_flash(@flash, :info)} 
 {live_flash(@flash, :error)} 
```

### Phoenix.Component.live_img_preview/1 (function)

Generates an image preview on the client for a selected file.

### Attributes - Phoenix.Component.live_img_preview/1 (function)

* `entry` (`Phoenix.LiveView.UploadEntry`) (required) - The `Phoenix.LiveView.UploadEntry` struct.
* `id` (`:string`) - the id of the img tag. Derived by default from the entry ref, but can be overridden as needed if you need to render a preview of the same entry multiple times on the same page. Defaults to `nil`.
* Global attributes are accepted.

### Examples - Phoenix.Component.live_img_preview/1 (function)

```heex
<.live_img_preview :for={entry <- @uploads.avatar.entries} entry={entry} width="75" />
```

When you need to use it multiple times, make sure that they have distinct ids

```heex
<.live_img_preview :for={entry <- @uploads.avatar.entries} entry={entry} width="75" />

<.live_img_preview :for={entry <- @uploads.avatar.entries} id={"modal-#{entry.ref}"} entry={entry} width="500" />
```

### Phoenix.Component.live_render/3 (function)

Renders a LiveView within a template.

This is useful in two situations:

* When rendering a child LiveView inside a LiveView.

* When rendering a LiveView inside a regular (non-live) controller/view.

Most other cases for shared functionality, including state management and user interactions, can be
[achieved with function components or LiveComponents](welcome.html#compartmentalize-state-markup-and-events-in-liveview)

### Options - Phoenix.Component.live_render/3 (function)

* `:session` - a map of binary keys with extra session data to be serialized and sent
to the client. All session data currently in the connection is automatically available
in LiveViews. You can use this option to provide extra data. Remember all session data is
serialized and sent to the client, so you should always keep the data in the session
to a minimum. For example, instead of storing a User struct, you should store the "user_id"
and load the User when the LiveView mounts.

* `:container` - an optional tuple for the HTML tag and DOM attributes to be used for the
LiveView container. For example: `{:li, style: "color: blue;"}`. By default it uses the module
definition container. See the "Containers" section below for more information.

* `:id` - both the DOM ID and the ID to uniquely identify a LiveView. An `:id` is
automatically generated when rendering root LiveViews but it is a required option when
rendering a child LiveView.

* `:sticky` - an optional flag to maintain the LiveView across live redirects, even if it is
nested within another LiveView. Note that this only works for LiveViews that are in the same
[live_session](`Phoenix.LiveView.Router.live_session/3`).
If you are rendering the sticky view within another LiveView, make sure that the sticky view
itself does not use the same layout. You can do so by returning `{:ok, socket, layout: false}`
from mount.

### Examples - Phoenix.Component.live_render/3 (function)

When rendering from a controller/view, you can call:

```heex
{live_render(@conn, MyApp.ThermostatLive)}
```

Or:

```heex
{live_render(@conn, MyApp.ThermostatLive, session: %{"home_id" => @home.id})}
```

Within another LiveView, you must pass the `:id` option:

```heex
{live_render(@socket, MyApp.ThermostatLive, id: "thermostat")}
```

### Containers - Phoenix.Component.live_render/3 (function)

When a LiveView is rendered, its contents are wrapped in a container. By default,
the container is a `div` tag with a handful of LiveView-specific attributes.

The container can be customized in different ways:

* You can change the default `container` on `use Phoenix.LiveView`:

      use Phoenix.LiveView, container: {:tr, id: "foo-bar"}

* You can override the container tag and pass extra attributes when calling `live_render`
(as well as on your `live` call in your router):

      live_render socket, MyLiveView, container: {:tr, class: "highlight"}

If you don't want the container to affect layout, you can use the CSS property
`display: contents` or a class that applies it, like Tailwind's `.contents`.

Beware if you set this to `:body`, as any content injected inside the body
(such as `Phoenix.LiveReload` features) will be discarded once the LiveView
connects

### Testing - Phoenix.Component.live_render/3 (function)

Note that `render_click/1` and other testing functions will send events to the root LiveView, and you will want to
`find_live_child/2` to interact with nested LiveViews in your live tests.

### Phoenix.Component.live_title/1 (function)

Renders a title with automatic prefix/suffix on `@page_title` updates.

### Attributes - Phoenix.Component.live_title/1 (function)

* `prefix` (`:string`) - A prefix added before the content of `inner_block`. Defaults to `nil`.
* `default` (`:string`) - The default title to use if the inner block is empty on regular or connected mounts. *Note*: empty titles, such as `nil` or an empty string, fall back to the default value. Defaults to `nil`.
* `suffix` (`:string`) - A suffix added after the content of `inner_block`. Defaults to `nil`.

### Slots - Phoenix.Component.live_title/1 (function)

* `inner_block` (required) - Content rendered inside the `title` tag.

### Examples - Phoenix.Component.live_title/1 (function)

```heex
<.live_title default="Welcome" prefix="MyApp · ">
  {assigns[:page_title]}
</.live_title>
```

```heex
<.live_title default="Welcome" suffix=" · MyApp">
  {assigns[:page_title]}
</.live_title>
```

### Phoenix.Component.portal/1 (function)

Renders a portal.

A portal is a component that teleports its content to another place in the DOM.
It is useful in cases where you need to render some content in another place, for
example due to overflow or [stacking context](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_positioned_layout/Stacking_context).

A portal consists of two parts:

1. The portal source: the component that should be teleported.
2. The portal target: the DOM element that will render the content of the portal source.

Any element can be a portal target. In most cases, the target would be rendered inside
the layout of your application. Portal sources must be defined with the `.portal` component.

### Examples - Phoenix.Component.portal/1 (function)

```heex
<.portal id="modal" target="body">
  ...
</.portal>
```

### Attributes - Phoenix.Component.portal/1 (function)

* `id` (`:string`) (required)
* `target` (`:string`) (required) - A CSS selector that identifies the target. The target must be unique.
* `class` (`:string`) - The class to apply to the portal wrapper. Defaults to `nil`.
* `container` (`:string`) - The HTML tag to use as the portal wrapper. Defaults to `"div"`.

### Slots - Phoenix.Component.portal/1 (function)

* `inner_block` (required)

### Phoenix.Component.render_slot/2 (macro)

Renders a slot entry with the given optional `argument`.

```heex
{render_slot(@inner_block, @form)}
```

If the slot has no entries, nil is returned.

If multiple slot entries are defined for the same slot,`render_slot/2` will automatically render
all entries, merging their contents. In case you want to use the entries' attributes, you need
to iterate over the list to access each slot individually.

For example, imagine a table component:

```heex
<.table rows={@users}>
  <:col :let={user} label="Name">
    {user.name}
  </:col>

  <:col :let={user} label="Address">
    {user.address}
  </:col>
</.table>
```

At the top level, we pass the rows as an assign and we define a `:col` slot for each column we
want in the table. Each column also has a `label`, which we are going to use in the table header.

Inside the component, you can render the table with headers, rows, and columns:

    def table(assigns) do
      ~H"""
       
         
           {col.label} 
         
         
           {render_slot(col, row)} 
         
       
      """
    end

### Phoenix.Component.sigil_H/2 (macro)

The `~H` sigil for writing HEEx templates inside source files.

`HEEx` is a HTML-aware and component-friendly extension of Elixir Embedded
language (`EEx`) that provides:

  * Built-in handling of HTML attributes

  * An HTML-like notation for injecting function components

  * Compile-time validation of the structure of the template

  * The ability to minimize the amount of data sent over the wire

  * Out-of-the-box code formatting via `mix format`

### Example - Phoenix.Component.sigil_H/2 (macro)

~H"""
     
       Hello {@name} 
       
     
    """

### Syntax - Phoenix.Component.sigil_H/2 (macro)

`HEEx` is built on top of Embedded Elixir (`EEx`). In this section, we are going to
cover the basic constructs in `HEEx` templates as well as its syntax extensions.

### Interpolation - Phoenix.Component.sigil_H/2 (macro)

`HEEx` allows using `{...}` for HTML-aware interpolation, inside tag attributes
as well as the body:

```heex
 Hello, {@name} 
```

If you want to interpolate an attribute, you write:

```heex
 
  ...
 
```

You can put any Elixir expression between `{ ... }`. For example, if you want
to set classes, where some are static and others are dynamic, you can using
string interpolation:

```heex
 
  ...
 
```

The following attribute values have special meaning on HTML tags:

* `true` - if a value is `true`, the attribute is rendered with no value at all.
  For example, ` ` is the same as ` `;

* `false` or `nil` - if a value is `false` or `nil`, the attribute is omitted.
  Note the `class` and `style` attributes will be rendered as empty strings,
  instead of ommitted, which has the same effect as not rendering them, but
  allows for rendering optimizations.

* `list` (only for the `class` attribute) - each element of the list is processed
  as a different class. `nil` and `false` elements are discarded. Nested lists
  are supported and flattened.

For multiple dynamic attributes, you can use the same notation but without
assigning the expression to any specific attribute:

```heex
 
  ...
 
```

In this case, the expression inside `{...}` must be either a keyword list or
a map containing the key-value pairs representing the dynamic attributes.
If using a map, ensure your keys are atoms.

### Interpolating blocks - Phoenix.Component.sigil_H/2 (macro)

The curly braces syntax is the default mechanism for interpolating code.
However, it cannot be used in all scenarios, in particular:

  * Curly braces cannot be used inside ` ` and ` ` tags,
    as that would make writing JS and CSS quite tedious. You can also
    fully disable curly braces interpolation in a given tag and
    its children by adding the `phx-no-curly-interpolation` attribute

  * it does not support multiline block constructs, such as `if`,
    `case`, and similar

For example, if you need to interpolate a string inside a script tag,
you could do:

```heex
 
  window.URL = "<%= @my_url %>"
 
```

Similarly, for block constructs in Elixir, you can write:

```heex
<%= if @show_greeting? do %>
   Hello, {@name} 
<% end %>
```

However, for conditionals and for-comprehensions, there are built-in constructs
in HEEx too, which we will explore next.

> #### Curly braces in text within tag bodies {: .tip}
>
> If you have text in your tag bodies, which includes curly braces you can use
> `&lbrace;` or `<%= "{" %>` to prevent them from being considered the start of
> interpolation.

### Special attributes - Phoenix.Component.sigil_H/2 (macro)

Apart from normal HTML attributes, HEEx also supports some special attributes
such as `:let` and `:for`.

#### :let

This is used by components and slots that want to yield a value back to the
caller. For an example, see how `form/1` works:

```heex
<.form :let={f} for={@form} phx-change="validate" phx-submit="save">
  <.input field={f[:username]} type="text" />
  ...
</.form>
```

Notice how the variable `f`, defined by `.form` is used by your `input` component.
The `Phoenix.Component` module has detailed documentation on how to use and
implement such functionality.

#### :if and :for

It is a syntax sugar for `<%= if .. do %>` and `<%= for .. do %>` that can be
used in regular HTML, function components, and slots.

For example in an HTML tag:

```heex
 
   
     {user.name} 
   
 
```

The snippet above will only render the table if `@admin?` is true,
and generate a `tr` per user as you would expect from the collection.

`:for` can be used similarly in function components:

```heex
<.error :for={msg <- @errors} message={msg}/>
```

Which is equivalent to writing:

```heex
<%= for msg <- @errors do %>
  <.error message={msg} />
<% end %>
```

And `:for` in slots behaves the same way:

```heex
<.table id="my-table" rows={@users}>
  <:col :for={header <- @headers} :let={user}>
     {user[header]} 
  </:col>
<.table>
```

You can also combine `:for` and `:if` for tags, components, and slot to act as a filter:

```heex
<.error :for={msg <- @errors} :if={msg != nil} message={msg} />
```

Note that unlike Elixir's regular `for`, HEEx' `:for` does not support multiple
generators in one expression. In such cases, you must use `EEx`'s blocks.

> #### Change tracking `:for` on slots {: .warning}
>
> Compared to regular HTML tags and components, LiveView does not
> optimize comprehensions on slots.
> This means that if `@headers` changes in the example above, all
> headers are sent over the wire again.
>
> Furthermore, `:key` (see below) is also not supported on slots
> right now.

#### `:key`ed comprehensions

When using `:for`, you can optionally provide a `:key` expression to perform
better change tracking inside the comprehension:

```heex
 
   
    Count:  {@count} ,
    item: {name}
   
 
```

By default, the index is used as a key, which means that appending an entry leads to
all items being considered changed. Therefore, we recommend to use a `:key` whenever possible.

Note that the `:key` has no effect when using [streams](`Phoenix.LiveView.stream/4`).

### Function components - Phoenix.Component.sigil_H/2 (macro)

Function components are stateless components implemented as pure functions
with the help of the `Phoenix.Component` module. They can be either local
(same module) or remote (external module).

`HEEx` allows invoking these function components directly in the template
using an HTML-like notation. For example, a remote function:

```heex
 
```

A local function can be invoked with a leading dot:

```heex
<.city name="Kraków"/>
```

where the component could be defined as follows:

    defmodule MyApp.Weather do
      use Phoenix.Component

      def city(assigns) do
        ~H"""
        The chosen city is: {@name}.
        """
      end

      def country(assigns) do
        ~H"""
        The chosen country is: {@name}.
        """
      end
    end

It is typically best to group related functions into a single module, as
opposed to having many modules with a single `render/1` function. Function
components support other important features, such as slots. You can learn
more about components in `Phoenix.Component`.

### Code formatting - Phoenix.Component.sigil_H/2 (macro)

You can automatically format HEEx templates (.heex) and `~H` sigils
using `Phoenix.LiveView.HTMLFormatter`. Please check that module
for more information.

### Phoenix.Component.slot/2 (macro)

Declares a slot. See `slot/3` for more information.

### Phoenix.Component.slot/3 (macro)

Declares a function component slot.

### Arguments - Phoenix.Component.slot/3 (macro)

* `name` - an atom defining the name of the slot. Note that slots cannot define the same name
as any other slots or attributes declared for the same component.

* `opts` - a keyword list of options. Defaults to `[]`.

* `block` - a code block containing calls to `attr/3`. Defaults to `nil`.

### Options - Phoenix.Component.slot/3 (macro)

* `:required` - marks a slot as required. If a caller does not pass a value for a required slot,
a compilation warning is emitted. Otherwise, an omitted slot will default to `[]`.

* `:validate_attrs` - when set to `false`, no warning is emitted when a caller passes attributes
to a slot defined without a do block. If not set, defaults to `true`.

* `:doc` - documentation for the slot. Any slot attributes declared
will have their documentation listed alongside the slot.

### Slot Attributes - Phoenix.Component.slot/3 (macro)

A named slot may declare attributes by passing a block with calls to `attr/3`.

Unlike attributes, slot attributes cannot accept the `:default` option. Passing one
will result in a compile warning being issued.

### The Default Slot - Phoenix.Component.slot/3 (macro)

The default slot can be declared by passing `:inner_block` as the `name` of the slot.

Note that the `:inner_block` slot declaration cannot accept a block. Passing one will
result in a compilation error.

### Compile-Time Validations - Phoenix.Component.slot/3 (macro)

LiveView performs some validation of slots via the `:phoenix_live_view` compiler.
When slots are defined, LiveView will warn at compilation time on the caller if:

* A required slot of a component is missing.

* An unknown slot is given.

* An unknown slot attribute is given.

On the side of the function component itself, defining attributes provides the following
quality of life improvements:

* Slot documentation is generated for the component.

* Calls made to the component are tracked for reflection and validation purposes.

### Documentation Generation - Phoenix.Component.slot/3 (macro)

Public function components that define slots will have their docs injected into the function's
documentation, depending on the value of the `@doc` module attribute:

* if `@doc` is a string, the slot docs are injected into that string. The optional placeholder
`[INSERT LVATTRDOCS]` can be used to specify where in the string the docs are injected.
Otherwise, the docs are appended to the end of the `@doc` string.

* if `@doc` is unspecified, the slot docs are used as the default `@doc` string.

* if `@doc` is `false`, the slot docs are omitted entirely.

The injected slot docs are formatted as a markdown list:

  * `name` (required) - slot docs. Accepts attributes:
    * `name` (`:type`) (required) - attr docs. Defaults to `:default`.

By default, all slots will have their docs injected into the function `@doc` string.
To hide a specific slot, you can set the value of `:doc` to `false`.

### Example - Phoenix.Component.slot/3 (macro)

slot :header
    slot :inner_block, required: true
    slot :footer

    def modal(assigns) do
      ~H"""
       
         
          {render_slot(@header) || "Modal"}
         
         
          {render_slot(@inner_block)}
         
         
          {render_slot(@footer) || submit_button()}
         
       
      """
    end

As shown in the example above, `render_slot/1` returns `nil` when an optional slot is declared
and none is given. This can be used to attach default behaviour.

### Phoenix.Component.to_form/2 (function)

Converts a given data structure to a `Phoenix.HTML.Form`.

This is commonly used to convert a map or an Ecto changeset
into a form to be given to the `form/1` component.

### Creating a form from params - Phoenix.Component.to_form/2 (function)

If you want to create a form based on `handle_event` parameters,
you could do:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains
the form parameters, which are expected to have string keys.

You can also specify a name to nest the parameters:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

### Creating a form from changesets - Phoenix.Component.to_form/2 (function)

When using changesets, the underlying data, form parameters, and
errors are retrieved from it. The `:as` option is automatically
computed too. For example, if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema

      schema "..." do
        ...
      end
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

In this case, once the form is submitted, the parameters will
be available under `%{"user" => user_params}`.

### Options - Phoenix.Component.to_form/2 (function)

* `:as` - the `name` prefix to be used in form inputs
  * `:id` - the `id` prefix to be used in form inputs
  * `:errors` - keyword list of errors (used by maps exclusively)
  * `:action` - The action that was taken against the form. This value can be
    used to distinguish between different operations such as the user typing
    into a form for validation, or submitting a form for a database insert.
    For example: `to_form(changeset, action: :validate)`,
    or `to_form(changeset, action: :save)`. The provided action is passed
    to the underlying `Phoenix.HTML.FormData` implementation options.

The underlying data may accept additional options when
converted to forms. For example, a map accepts `:errors`
to list errors, but such option is not accepted by
changesets. `:errors` is a keyword of tuples in the shape
of `{error_message, options_list}`. Here is an example:

    to_form(%{"search" => nil}, errors: [search: {"Can't be blank", []}])

If an existing `Phoenix.HTML.Form` struct is given, the
options above will override its existing values if given.
Then the remaining options are merged with the existing
form options.

Errors in a form are only displayed if the changeset's `action`
field is set (and it is not set to `:ignore`) and can be filtered
by whether the fields have been used on the client or not. Refer to
[a note on :errors for more information](#form/1-a-note-on-errors).

### Phoenix.Component.update/3 (function)

Updates an existing `key` with `fun` in the given `socket_or_assigns`.

The first argument is either a LiveView `socket` or an `assigns` map from function components.

The update function receives the current key's value and returns the updated value.
Raises if the key does not exist.

The update function may also be of arity 2, in which case it receives the current key's value
as the first argument and the current assigns as the second argument.
Raises if the key does not exist.

### Examples - Phoenix.Component.update/3 (function)

iex> update(socket, :count, fn count -> count + 1 end)
    iex> update(socket, :count, &(&1 + 1))
    iex> update(socket, :max_users_this_session, fn current_max, %{users: users} ->
    ...>   max(current_max, length(users))
    ...> end)

### Phoenix.Component.upload_errors/1 (function)

Returns errors for the upload as a whole.

For errors that apply to a specific upload entry, use `upload_errors/2`.

The output is a list. The following error may be returned:

* `:too_many_files` - The number of selected files exceeds the `:max_entries` constraint

### Examples - Phoenix.Component.upload_errors/1 (function)

def upload_error_to_string(:too_many_files), do: "You have selected too many files"

```heex
 
  {upload_error_to_string(err)}
 
```

### Phoenix.Component.upload_errors/2 (function)

Returns errors for the upload entry.

For errors that apply to the upload as a whole, use `upload_errors/1`.

The output is a list. The following errors may be returned:

* `:too_large` - The entry exceeds the `:max_file_size` constraint
* `:not_accepted` - The entry does not match the `:accept` MIME types
* `:external_client_failure` - When external upload fails
* `{:writer_failure, reason}` - When the custom writer fails with `reason`

### Examples - Phoenix.Component.upload_errors/2 (function)

```elixir
defp upload_error_to_string(:too_large), do: "The file is too large"
defp upload_error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
defp upload_error_to_string(:external_client_failure), do: "Something went terribly wrong"
```

```heex
<%= for entry <- @uploads.avatar.entries do %>
   
    {upload_error_to_string(err)}
   
<% end %>
```

### Phoenix.Component.used_input?/1 (function)

Checks if the input field was used by the client.

Used inputs are only those inputs that have been focused, interacted with, or
submitted by the client. For LiveView, this is used to filter errors from the
`Phoenix.HTML.FormData` implementation to avoid showing "field can't be blank"
in scenarios where the client hasn't yet interacted with specific fields.

Used inputs are tracked internally by the client sending a sibling key
derived from each input name, which indicates the inputs that remain  unused
on the client. For example, a form with email and title fields where only the
title has been modified so far on the client, would send the following payload:

    %{
      "title" => "new title",
      "email" => "",
      "_unused_email" => ""
    }

The `_unused_email` key indicates that the email field has not been used by the
client, which is used to filter errors from the UI.

Nested fields are also supported. For example, a form with a nested datetime field
is considered used if any of the nested parameters are used.

    %{
      "bday" => %{
        "year" => "",
        "month" => "",
        "day" => "",
        "_unused_day" => ""
      }
    }

The `_unused_day` key indicates that the day field has not been used by the client,
but the year and month fields have been used, meaning the birthday field as a whole
was used.

### Examples - Phoenix.Component.used_input?/1 (function)

For example, imagine in your template you render a title and email input.
On initial load the end-user begins typing the title field. The client will send
the entire form payload to the server with the typed title and an empty email.

The `Phoenix.HTML.FormData` implementation will consider an empty email in
this scenario as invalid, but the user shouldn't see the error because they
haven't yet used the email input. To handle this, `used_input?/1` can be used to
filter errors from the client by referencing param metadata to distinguish between
used and unused input fields. For non-LiveViews, all inputs are considered used.

```heex
 

 
   {error} 
 

 

 
   {error} 
 
```

### Phoenix.LiveComponent (behaviour)

LiveComponents are a mechanism to compartmentalize state, markup, and
events for sharing across LiveViews.

LiveComponents are defined by using `Phoenix.LiveComponent` and are used
by calling `Phoenix.Component.live_component/1` in a parent LiveView.
They run inside the LiveView process but have their own state and
life-cycle. For this reason, they are also often called "stateful components".
This is a contrast to `Phoenix.Component`, also known as "function components",
which are stateless and do not have a life-cycle.

The smallest LiveComponent only needs to define a `c:render/1` function:

    defmodule HeroComponent do
      # In Phoenix apps, the line is typically: use MyAppWeb, :live_component
      use Phoenix.LiveComponent

      def render(assigns) do
        ~H"""
         {@content} 
        """
      end
    end

A LiveComponent is rendered as:

```heex
<.live_component module={HeroComponent} id="hero" content={@content} />
```

You must always pass the `module` and `id` attributes. The `id` will be
available as an assign and it must be used to uniquely identify the
component. All other attributes will be available as assigns inside the
LiveComponent.

> #### Functional components or live components? {: .neutral}
>
> Generally speaking, you should prefer function components over live
> components, as they are a simpler abstraction, with a smaller surface
> area. The use case for live components only arises when there is a need
> for encapsulating both event handling and additional state.
>
> Similarly, avoid using LiveComponents for code design purposes, where
> their main goal is to organize code, rather than sharing it across
> LiveViews. When it comes to code organization and design, Elixir developers
> prefer to use functions and data structures.

### Life-cycle - Phoenix.LiveComponent (behaviour)



### Mount and update - Phoenix.LiveComponent (behaviour)

Live components are identified by the component module and their ID.
We often tie the component ID to some application based ID:

```heex
<.live_component module={UserComponent} id={@user.id} user={@user} />
```

When [`live_component/1`](`Phoenix.Component.live_component/1`) is called,
`c:mount/1` is called once, when the component is first added to the page.
`c:mount/1` receives a `socket` as its argument. Note that this is *not* the
same `socket` struct from the parent LiveView. It doesn't contain the parent
LiveView's `assigns`, and updating it won't affect the parent LiveView's
`socket`.

Then `c:update/2` is invoked with all of the assigns passed to
[`live_component/1`](`Phoenix.Component.live_component/1`). The assigns
received as the first argument to `c:update/2` will only include those
assigns given to [`live_component/1`](`Phoenix.Component.live_component/1`),
and not any pre-existing assigns in `socket.assigns` such as those assigned
by `c:mount/1`.

If `c:update/2` is not defined then all assigns given to
[`live_component/1`](`Phoenix.Component.live_component/1`) will simply be
merged into `socket.assigns`.

Both `c:mount/1` and `c:update/2` must return a tuple whose first element is
`:ok` and whose second element is the updated `socket`.

After the component is updated, `c:render/1` is called with all assigns.
On first render, we get:

    mount(socket) -> update(assigns, socket) -> render(assigns)

On further rendering:

    update(assigns, socket) -> render(assigns)

Two live components with the same module and ID are treated as the same component,
regardless of where they are in the page. Therefore, if you change the location
of where a component is rendered within its parent LiveView, it won't be remounted.
This means you can use live components to implement cards and other elements that
can be moved around without losing state. A component is only discarded when the
client observes it is removed from the page.

Finally, the given `id` is not automatically used as the DOM ID. If you want to set
a DOM ID, it is your responsibility to do so when rendering:

    defmodule UserComponent do
      # In Phoenix apps, the line is typically: use MyAppWeb, :live_component
      use Phoenix.LiveComponent

      def render(assigns) do
        ~H"""
         
          {@user.name}
         
        """
      end
    end

### Events - Phoenix.LiveComponent (behaviour)

LiveComponents can also implement the `c:handle_event/3` callback
that works exactly the same as in LiveView. For a client event to
reach a component, the tag must be annotated with a `phx-target`.
If you want to send the event to yourself, you can simply use the
`@myself` assign, which is an *internal unique reference* to the
component instance:

```heex
 
  Say hello!
 
```

Note that `@myself` is not set for stateless components, as they cannot
receive events.

If you want to target another component, you can also pass an ID
or a class selector to any element inside the targeted component.
For example, if there is a `UserComponent` with the DOM ID of `"user-13"`,
using a query selector, we can send an event to it with:

```heex
 
  Say hello!
 
```

In both cases, `c:handle_event/3` will be called with the
"say_hello" event. When `c:handle_event/3` is called for a component,
only the diff of the component is sent to the client, making them
extremely efficient.

Any valid query selector for `phx-target` is supported, provided that the
matched nodes are children of a LiveView or LiveComponent, for example
to send the `close` event to multiple components:

```heex
 
  Dismiss
 
```

### Update many - Phoenix.LiveComponent (behaviour)

Live components also support an optional `c:update_many/1` callback
as an alternative to `c:update/2`. While `c:update/2` is called for
each component individually, `c:update_many/1` is called with all
LiveComponents of the same module being currently rendered/updated.
The advantage is that you can preload data from the database using
a single query for all components, instead of running one query per
component.

To provide a more complete understanding of why both callbacks are necessary,
let's see an example. Imagine you are implementing a component and the component
needs to load some state from the database. For example:

```heex
<.live_component module={UserComponent} id={user_id} />
```

A possible implementation would be to load the user on the `c:update/2`
callback:

    def update(assigns, socket) do
      user = Repo.get!(User, assigns.id)
      {:ok, assign(socket, :user, user)}
    end

However, the issue with said approach is that, if you are rendering
multiple user components in the same page, you have a N+1 query problem.
By using `c:update_many/1` instead of `c:update/2` , we receive a list
of all assigns and sockets, allowing us to update many at once:

    def update_many(assigns_sockets) do
      list_of_ids = Enum.map(assigns_sockets, fn {assigns, _socket} -> assigns.id end)

      users =
        from(u in User, where: u.id in ^list_of_ids, select: {u.id, u})
        |> Repo.all()
        |> Map.new()

      Enum.map(assigns_sockets, fn {assigns, socket} ->
        assign(socket, :user, users[assigns.id])
      end)
    end

Now only a single query to the database will be made. In fact, the
`update_many/1` algorithm is a breadth-first tree traversal, which means
that even for nested components, the amount of queries are kept to
a minimum.

Finally, note that `c:update_many/1` must return an updated list of
sockets in the same order as they are given. If `c:update_many/1` is
defined, `c:update/2` is not invoked.

### Summary - Phoenix.LiveComponent (behaviour)

All of the life-cycle events are summarized in the diagram below.
The bubble events in white are triggers that invoke the component.
In blue you have component callbacks, where the underlined names
represent required callbacks:

```mermaid
flowchart LR
    *((start)):::event-.->M
    WE([wait for parent changes]):::event-.->M
    W([wait for events]):::event-.->H

    subgraph j__transparent[" "]

      subgraph i[" "]
        direction TB
        M(mount/1  only once ):::callback
        M-->U
        M-->UM
      end

      U(update/2):::callback-->A
      UM(update_many/1):::callback-->A

      subgraph j[" "]
        direction TB
        A --> |yes| R
        H(handle_event/3):::callback-->A{any changes?}:::diamond
      end

      A --> |no| W

    end

    R(render/1):::callback_req-->W

    classDef event fill:#fff,color:#000,stroke:#000
    classDef diamond fill:#FFC28C,color:#000,stroke:#000
    classDef callback fill:#B7ADFF,color:#000,stroke-width:0
    classDef callback_req fill:#B7ADFF,color:#000,stroke-width:0,text-decoration:underline
```

### Managing state - Phoenix.LiveComponent (behaviour)

Now that we have learned how to define and use components, as well as
how to use `c:update_many/1` as a data loading optimization, it is important
to talk about how to manage state in components.

Generally speaking, you want to avoid both the parent LiveView and the
LiveComponent working on two different copies of the state. Instead, you
should assume only one of them to be the source of truth. Let's discuss
the two different approaches in detail.

Imagine a scenario where a LiveView represents a board with each card
in it as a separate LiveComponent. Each card has a form to
allow update of the card title directly in the component, as follows:

    defmodule CardComponent do
      use Phoenix.LiveComponent

      def render(assigns) do
        ~H"""
         
           {@card.title} 
          ...
         
        """
      end

      ...
    end

We will see how to organize the data flow to keep either the board LiveView or
the card LiveComponents as the source of truth.

### LiveView as the source of truth - Phoenix.LiveComponent (behaviour)

If the board LiveView is the source of truth, it will be responsible
for fetching all of the cards in a board. Then it will call
[`live_component/1`](`Phoenix.Component.live_component/1`)
for each card, passing the card struct as argument to `CardComponent`:

```heex
<.live_component
  :for={card <- @cards}
  module={CardComponent}
  card={card}
  id={card.id}
  board_id={@id}
/>
```

Now, when the user submits the form, `CardComponent.handle_event/3`
will be triggered. However, if the update succeeds, you must not
change the card struct inside the component. If you do so, the card
struct in the component will get out of sync with the LiveView.  Since
the LiveView is the source of truth, you should instead tell the
LiveView that the card was updated.

Luckily, because the component and the view run in the same process,
sending a message from the LiveComponent to the parent LiveView is as
simple as sending a message to `self()`:

    defmodule CardComponent do
      ...
      def handle_event("update_title", %{"title" => title}, socket) do
        send self(), {:updated_card, %{socket.assigns.card | title: title}}
        {:noreply, socket}
      end
    end

The LiveView then receives this event using `c:Phoenix.LiveView.handle_info/2`:

    defmodule BoardView do
      ...
      def handle_info({:updated_card, card}, socket) do
        # update the list of cards in the socket
        {:noreply, updated_socket}
      end
    end

Because the list of cards in the parent socket was updated, the parent
LiveView will be re-rendered, sending the updated card to the component.
So in the end, the component does get the updated card, but always
driven from the parent.

Alternatively, instead of having the component send a message directly to the
parent view, the component could broadcast the update using `Phoenix.PubSub`.
Such as:

    defmodule CardComponent do
      ...
      def handle_event("update_title", %{"title" => title}, socket) do
        message = {:updated_card, %{socket.assigns.card | title: title}}
        Phoenix.PubSub.broadcast(MyApp.PubSub, board_topic(socket), message)
        {:noreply, socket}
      end

      defp board_topic(socket) do
        "board:" <> socket.assigns.board_id
      end
    end

As long as the parent LiveView subscribes to the `board: ` topic,
it will receive updates. The advantage of using PubSub is that we get
distributed updates out of the box. Now, if any user connected to the
board changes a card, all other users will see the change.

### LiveComponent as the source of truth - Phoenix.LiveComponent (behaviour)

If each card LiveComponent is the source of truth, then the board LiveView
must no longer fetch the card structs from the database. Instead, the board
LiveView must only fetch the card ids, then render each component only by
passing an ID:

```heex
<.live_component
  :for={card_id <- @card_ids}
  module={CardComponent}
  id={card_id}
  board_id={@id}
/>
```

Now, each CardComponent will load its own card. Of course, doing so
per card could be expensive and lead to N queries, where N is the
number of cards, so we can use the `c:update_many/1` callback to make it
efficient.

Once the card components are started, they can each manage their own
card, without concerning themselves with the parent LiveView.

However, note that components do not have a `c:Phoenix.LiveView.handle_info/2`
callback. Therefore, if you want to track distributed changes on a card,
you must have the parent LiveView receive those events and redirect them
to the appropriate card. For example, assuming card updates are sent
to the "board:ID" topic, and that the board LiveView is subscribed to
said topic, one could do:

    def handle_info({:updated_card, card}, socket) do
      send_update CardComponent, id: card.id, board_id: socket.assigns.id
      {:noreply, socket}
    end

With `Phoenix.LiveView.send_update/3`, the `CardComponent` given by `id`
will be invoked, triggering the update or update_many callback, which will
load the most up to date data from the database.

### Unifying LiveView and LiveComponent communication - Phoenix.LiveComponent (behaviour)

In the examples above, we have used `send/2` to communicate with LiveView
and `send_update/2` to communicate with components. This introduces a problem:
what if you have a component that may be mounted both inside a LiveView
or another component? Given each uses a different API for exchanging data,
this may seem tricky at first, but an elegant solution is to use anonymous
functions as callbacks. Let's see an example.

In the sections above, we wrote the following code in our `CardComponent`:

```elixir
def handle_event("update_title", %{"title" => title}, socket) do
  send self(), {:updated_card, %{socket.assigns.card | title: title}}
  {:noreply, socket}
end
```

The issue with this code is that, if CardComponent is mounted inside another
component, it will still message the LiveView. Not only that, this code may
be hard to maintain because the message sent by the component is defined far
away from the LiveView that will receive it.

Instead let's define a callback that will be invoked by CardComponent:

```elixir
def handle_event("update_title", %{"title" => title}, socket) do
  socket.assigns.on_card_update.(%{socket.assigns.card | title: title})
  {:noreply, socket}
end
```

And now when initializing the CardComponent from a LiveView, we may write:

```heex
<.live_component
  module={CardComponent}
  card={card}
  id={card.id}
  board_id={@id}
  on_card_update={fn card -> send(self(), {:updated_card, card}) end} />
```

If initializing it inside another component, one may write:

```heex
<.live_component
  module={CardComponent}
  card={card}
  id={card.id}
  board_id={@id}
  on_card_update={fn card -> send_update(@myself, card: card) end} />
```

The major benefit in both cases is that the parent has explicit control
over the messages it will receive.

### Slots - Phoenix.LiveComponent (behaviour)

LiveComponent can also receive slots, in the same way as a `Phoenix.Component`:

```heex
<.live_component module={MyComponent} id={@data.id} >
   Inner content here 
</.live_component>
```

If the LiveComponent defines an `c:update/2`, be sure that the socket it returns
includes the `:inner_block` assign it received.

See [the docs](Phoenix.Component.html#module-slots.md) for `Phoenix.Component` for more information.

### Live patches and live redirects - Phoenix.LiveComponent (behaviour)

A template rendered inside a component can use `<.link patch={...}>` and
`<.link navigate={...}>`. Patches are always handled by the parent LiveView,
as components do not provide `handle_params`.

### Cost of live components - Phoenix.LiveComponent (behaviour)

The internal infrastructure LiveView uses to keep track of live
components is very lightweight. However, be aware that in order to
provide change tracking and to send diffs over the wire, all of the
components' assigns are kept in memory - exactly as it is done in
LiveViews themselves.

Therefore it is your responsibility to keep only the assigns necessary
in each component. For example, avoid passing all of LiveView's assigns
when rendering a component:

```heex
<.live_component module={MyComponent} {assigns} />
```

Instead pass only the keys that you need:

```heex
<.live_component module={MyComponent} user={@user} org={@org} />
```

Luckily, because LiveViews and LiveComponents are in the same process,
they share the data structure representations in memory. For example,
in the code above, the view and the component will share the same copies
of the `@user` and `@org` assigns.

You should also avoid using live components to provide abstract DOM
components. As a guideline, a good LiveComponent encapsulates
application concerns and not DOM functionality. For example, if you
have a page that shows products for sale, you can encapsulate the
rendering of each of those products in a component. This component
may have many buttons and events within it. On the opposite side,
do not write a component that is simply encapsulating generic DOM
components. For instance, do not do this:

    defmodule MyButton do
      use Phoenix.LiveComponent

      def render(assigns) do
        ~H"""
         
          {@text}
         
        """
      end

      def handle_event("click", _, socket) do
        _ = socket.assigns.on_click.()
        {:noreply, socket}
      end
    end

Instead, it is much simpler to create a function component:

    def my_button(%{text: _, click: _} = assigns) do
      ~H"""
       
        {@text}
       
      """
    end

If you keep components mostly as an application concern with
only the necessary assigns, it is unlikely you will run into
issues related to live components.

### Limitations - Phoenix.LiveComponent (behaviour)

Live Components require a single HTML tag at the root. It is not possible
to have components that render only text or multiple tags.

### Phoenix.LiveComponent.__using__/1 (macro)

Uses LiveComponent in the current module.

    use Phoenix.LiveComponent

### Options - Phoenix.LiveComponent.__using__/1 (macro)

* `:global_prefixes` - the global prefixes to use for components. See
    `Global Attributes` in `Phoenix.Component` for more information.

### Phoenix.LiveComponent.handle_async/3 (callback)



### Phoenix.LiveComponent.handle_event/3 (callback)



### Phoenix.LiveComponent.mount/1 (callback)



### Phoenix.LiveComponent.render/1 (callback)



### Phoenix.LiveComponent.update/2 (callback)



### Phoenix.LiveComponent.update_many/1 (callback)



### Phoenix.LiveView (behaviour)

A LiveView is a process that receives events, updates
its state, and renders updates to a page as diffs.

To get started, see [the Welcome guide](welcome.md).
This module provides advanced documentation and features
about using LiveView.

### Life-cycle - Phoenix.LiveView (behaviour)

A LiveView begins as a regular HTTP request and HTML response,
and then upgrades to a stateful view on client connect,
guaranteeing a regular HTML page even if JavaScript is disabled.
Any time a stateful view changes or updates its socket assigns, it is
automatically re-rendered and the updates are pushed to the client.

Socket assigns are stateful values kept on the server side in
`Phoenix.LiveView.Socket`. This is different from the common stateless
HTTP pattern of sending the connection state to the client in the form
of a token or cookie and rebuilding the state on the server to service
every request.

You begin by rendering a LiveView typically from your router.
When LiveView is first rendered, the `c:mount/3` callback is invoked
with the current params, the current session and the LiveView socket.
As in a regular request, `params` contains public data that can be
modified by the user. The `session` always contains private data set
by the application itself. The `c:mount/3` callback wires up socket
assigns necessary for rendering the view. After mounting, `c:handle_params/3`
is invoked so uri and query params are handled. Finally, `c:render/1`
is invoked and the HTML is sent as a regular HTML response to the
client.

After rendering the static page, LiveView connects from the client
to the server where stateful views are spawned to push rendered updates
to the browser, and receive client events via `phx-` bindings. Just like
the first rendering, `c:mount/3`, is invoked  with params, session,
and socket state. However in the connected client case, a LiveView process
is spawned on the server, runs `c:handle_params/3` again and then pushes
the result of `c:render/1` to the client and continues on for the duration
of the connection. If at any point during the stateful life-cycle a crash
is encountered, or the client connection drops, the client gracefully
reconnects to the server, calling `c:mount/3` and `c:handle_params/3` again.

LiveView also allows attaching hooks to specific life-cycle stages with
`attach_hook/4`.

### Template collocation - Phoenix.LiveView (behaviour)

There are two possible ways of rendering content in a LiveView. The first
one is by explicitly defining a render function, which receives `assigns`
and returns a `HEEx` template defined with [the `~H` sigil](`Phoenix.Component.sigil_H/2`).

    defmodule MyAppWeb.DemoLive do
      # In a typical Phoenix app, the following line would usually be `use MyAppWeb, :live_view`
      use Phoenix.LiveView

      def render(assigns) do
        ~H"""
        Hello world!
        """
      end
    end

For larger templates, you can place them in a file in the same directory
and same name as the LiveView. For example, if the file above is placed
at `lib/my_app_web/live/demo_live.ex`, you can also remove the
`render/1` function altogether and put the template code at
`lib/my_app_web/live/demo_live.html.heex`.

### Async Operations - Phoenix.LiveView (behaviour)

Performing asynchronous work is common in LiveViews and LiveComponents.
It allows the user to get a working UI quickly while the system fetches some
data in the background or talks to an external service, without blocking the
render or event handling. For async work, you also typically need to handle
the different states of the async operation, such as loading, error, and the
successful result. You also want to catch any errors or exits and translate it
to a meaningful update in the UI rather than crashing the user experience.

### Async assigns - Phoenix.LiveView (behaviour)

The `assign_async/3` function takes the socket, a key or list of keys which will be assigned
asynchronously, and a function. This function will be wrapped in a `task` by
`assign_async`, making it easy for you to return the result. This function must
return an `{:ok, assigns}` or `{:error, reason}` tuple, where `assigns` is a map
of the keys passed to `assign_async`.
If the function returns anything else, an error is raised.

The task is only started when the socket is connected.

For example, let's say we want to async fetch a user's organization from the database,
as well as their profile and rank:

    def mount(%{"slug" => slug}, _, socket) do
      {:ok,
       socket
       |> assign(:foo, "bar")
       |> assign_async(:org, fn -> {:ok, %{org: fetch_org!(slug)}} end)
       |> assign_async([:profile, :rank], fn -> {:ok, %{profile: ..., rank: ...}} end)}
    end

>

### Warning - Phoenix.LiveView (behaviour)

>
> When using async operations it is important to not pass the socket into the function
> as it will copy the whole socket struct to the Task process, which can be very expensive.
>
> Instead of:
>
> ```elixir
> assign_async(:org, fn -> {:ok, %{org: fetch_org(socket.assigns.slug)}} end)
> ```
>
> We should do:
>
> ```elixir
> slug = socket.assigns.slug
> assign_async(:org, fn -> {:ok, %{org: fetch_org(slug)}} end)
> ```
>
> See: https://hexdocs.pm/elixir/process-anti-patterns.html#sending-unnecessary-data

The state of the async operation is stored in the socket assigns within an
`Phoenix.LiveView.AsyncResult`. It carries the loading and failed states, as
well as the result. For example, if we wanted to show the loading states in
the UI for the `:org`, our template could conditionally render the states:

```heex
 Loading organization... 
 {org.name} loaded! 
```

The `Phoenix.Component.async_result/1` function component can also be used to
declaratively render the different states using slots:

```heex
<.async_result :let={org} assign={@org}>
  <:loading>Loading organization...</:loading>
  <:failed :let={_failure}>there was an error loading the organization</:failed>
  {org.name}
</.async_result>
```

### Arbitrary async operations - Phoenix.LiveView (behaviour)

Sometimes you need lower level control of asynchronous operations, while
still receiving process isolation and error handling. For this, you can use
`start_async/3` and the `Phoenix.LiveView.AsyncResult` module directly:

    def mount(%{"id" => id}, _, socket) do
      {:ok,
       socket
       |> assign(:org, AsyncResult.loading())
       |> start_async(:my_task, fn -> fetch_org!(id) end)}
    end

    def handle_async(:my_task, {:ok, fetched_org}, socket) do
      %{org: org} = socket.assigns
      {:noreply, assign(socket, :org, AsyncResult.ok(org, fetched_org))}
    end

    def handle_async(:my_task, {:exit, reason}, socket) do
      %{org: org} = socket.assigns
      {:noreply, assign(socket, :org, AsyncResult.failed(org, {:exit, reason}))}
    end

`start_async/3` is used to fetch the organization asynchronously. The
`c:handle_async/3` callback is called when the task completes or exits,
with the results wrapped in either `{:ok, result}` or `{:exit, reason}`.
The `AsyncResult` module provides functions to update the state of the
async operation, but you can also assign any value directly to the socket
if you want to handle the state yourself.

### Endpoint configuration - Phoenix.LiveView (behaviour)

LiveView accepts the following configuration in your endpoint under
the `:live_view` key:

  * `:signing_salt` (required) - the salt used to sign data sent
    to the client

  * `:hibernate_after` (optional) - the idle time in milliseconds allowed in
  the LiveView before compressing its own memory and state.
  Defaults to 15000ms (15 seconds)

### Phoenix.LiveView.__live__/1 (function)

Defines metadata for a LiveView.

This must be returned from the `__live__` callback.

It accepts:

  * `:container` - an optional tuple for the HTML tag and DOM attributes to
    be used for the LiveView container. For example: `{:li, style: "color: blue;"}`.

  * `:layout` - configures the layout the LiveView will be rendered in.
    This layout can be overridden by on `c:mount/3` or via the `:layout`
    option in `Phoenix.LiveView.Router.live_session/2`

  * `:log` - configures the log level for the LiveView, either `false`
    or a log level

  * `:on_mount` - a list of tuples with module names and argument to be invoked
    as `on_mount` hooks

### Phoenix.LiveView.__using__/1 (macro)

Uses LiveView in the current module to mark it a LiveView.

    use Phoenix.LiveView,
      container: {:tr, class: "colorized"},
      layout: {MyAppWeb.Layouts, :app},
      log: :info

### Options - Phoenix.LiveView.__using__/1 (macro)

* `:container` - an optional tuple for the HTML tag and DOM attributes to
    be used for the LiveView container. For example: `{:li, style: "color: blue;"}`.
    See `Phoenix.Component.live_render/3` for more information and examples.

  * `:global_prefixes` - the global prefixes to use for components. See
    `Global Attributes` in `Phoenix.Component` for more information.

  * `:layout` - configures the layout the LiveView will be rendered in.
    This layout can be overridden by on `c:mount/3` or via the `:layout`
    option in `Phoenix.LiveView.Router.live_session/2`

  * `:log` - configures the log level for the LiveView, either `false`
    or a log level

### Phoenix.LiveView.allow_upload/3 (function)

Allows an upload for the provided name.

### Options - Phoenix.LiveView.allow_upload/3 (function)

* `:accept` - Required. A list of unique file extensions (such as ".jpeg") or
    mime type (such as "image/jpeg" or "image/*"). You may also pass the atom
    `:any` instead of a list to support to allow any kind of file.
    For example, `[".jpeg"]`, `:any`, etc.

  * `:max_entries` - The maximum number of selected files to allow per
    file input. Defaults to 1.

  * `:max_file_size` - The maximum file size in bytes to allow to be uploaded.
    Defaults 8MB. For example, `12_000_000`.

  * `:chunk_size` - The chunk size in bytes to send when uploading.
    Defaults `64_000`.

  * `:chunk_timeout` - The time in milliseconds to wait before closing the
    upload channel when a new chunk has not been received. Defaults to `10_000`.

  * `:external` - A 2-arity function for generating metadata for external
    client uploaders. This function must return either `{:ok, meta, socket}`
    or `{:error, meta, socket}` where meta is a map. See the Uploads section
    for example usage.

  * `:progress` - An optional 3-arity function for receiving progress events.

  * `:auto_upload` - Instructs the client to upload the file automatically
    on file selection instead of waiting for form submits. Defaults to `false`.

  * `:writer` - A module implementing the `Phoenix.LiveView.UploadWriter`
    behaviour to use for writing the uploaded chunks. Defaults to writing to a
    temporary file for consumption. See the `Phoenix.LiveView.UploadWriter` docs
    for custom usage.

Raises when a previously allowed upload under the same name is still active.

### Examples - Phoenix.LiveView.allow_upload/3 (function)

allow_upload(socket, :avatar, accept: ~w(.jpg .jpeg), max_entries: 2)
    allow_upload(socket, :avatar, accept: :any)

For consuming files automatically as they are uploaded, you can pair `auto_upload: true` with
a custom progress function to consume the entries as they are completed. For example:

    allow_upload(socket, :avatar, accept: :any, progress: &handle_progress/3, auto_upload: true)

    defp handle_progress(:avatar, entry, socket) do
      if entry.done? do
        uploaded_file =
          consume_uploaded_entry(socket, entry, fn %{} = meta ->
            {:ok, ...}
          end)

        {:noreply, put_flash(socket, :info, "file #{uploaded_file.name} uploaded")}
      else
        {:noreply, socket}
      end
    end

### Phoenix.LiveView.assign_async/4 (macro)

Assigns keys asynchronously.

Wraps your function in a task linked to the caller, errors are wrapped.
Each key passed to `assign_async/3` will be assigned to
an `Phoenix.LiveView.AsyncResult` struct holding the status of the operation
and the result when the function completes.

The task is only started when the socket is connected.

### Options - Phoenix.LiveView.assign_async/4 (macro)

* `:supervisor` - allows you to specify a `Task.Supervisor` to supervise the task.
  * `:reset` - remove previous results during async operation when true. Possible values are
    `true`, `false`, or a list of keys to reset. Defaults to `false`.

### Examples - Phoenix.LiveView.assign_async/4 (macro)

```elixir
def mount(%{"slug" => slug}, _, socket) do
  {:ok,
    socket
    |> assign(:foo, "bar")
    |> assign_async(:org, fn -> {:ok, %{org: fetch_org!(slug)}} end)
    |> assign_async([:profile, :rank], fn -> {:ok, %{profile: ..., rank: ...}} end)}
end
```

See [Async Operations](#module-async-operations) for more information.

## `assign_async/3` and `send_update/3`

Since the code inside `assign_async/3` runs in a separate process,
`send_update(Component, data)` does not work inside `assign_async/3`,
since `send_update/2` assumes it is running inside the LiveView process.
The solution is to explicitly send the update to the LiveView:

```elixir
parent = self()
assign_async(socket, :org, fn ->
  # ...
  send_update(parent, Component, data)
end)
```

### Testing async operations - Phoenix.LiveView.assign_async/4 (macro)

When testing LiveViews and LiveComponents with async assigns, use
`Phoenix.LiveViewTest.render_async/2` to ensure the test waits until the async operations
are complete before proceeding with assertions or before ending the test. For example:

```elixir
{:ok, view, _html} = live(conn, "/my_live_view")
html = render_async(view)
assert html =~ "My assertion"
```

Not calling `render_async/2` to ensure all async assigns have finished might result in errors in
cases where your process has side effects:

```
[error] MyXQL.Connection (#PID<0.308.0>) disconnected: ** (DBConnection.ConnectionError) client #PID<0.794.0>
```

### Phoenix.LiveView.attach_hook/4 (function)

Attaches the given `fun` by `name` for the lifecycle `stage` into `socket`.

> Note: This function is for server-side lifecycle callbacks.
> For client-side hooks, see the
> [JS Interop guide](js-interop.html#client-hooks-via-phx-hook).

Hooks provide a mechanism to tap into key stages of the LiveView
lifecycle in order to bind/update assigns, intercept events,
patches, and regular messages when necessary, and to inject
common functionality. Use `attach_hook/4` on any of the following
lifecycle stages: `:handle_params`, `:handle_event`, `:handle_info`, `:handle_async`, and
`:after_render`. To attach a hook to the `:mount` stage, use `on_mount/1`.

> Note: only `:after_render` and `:handle_event` hooks are currently supported in
> LiveComponents.

### Return Values - Phoenix.LiveView.attach_hook/4 (function)

Lifecycle hooks take place immediately before a given lifecycle
callback is invoked on the LiveView. With the exception of `:after_render`,
a hook may return `{:halt, socket}` to halt the reduction, otherwise
it must return `{:cont, socket}` so the operation may continue until
all hooks have been invoked for the current stage.

For `:after_render` hooks, the `socket` itself must be returned.
Any updates to the socket assigns *will not* trigger a new render
or diff calculation to the client.

### Halting the lifecycle - Phoenix.LiveView.attach_hook/4 (function)

Note that halting from a hook _will halt the entire lifecycle stage_.
This means that when a hook returns `{:halt, socket}` then the
LiveView callback will **not** be invoked. This has some
implications.

### Implications for plugin authors - Phoenix.LiveView.attach_hook/4 (function)

When defining a plugin that matches on specific callbacks, you **must**
define a catch-all clause, as your hook will be invoked even for events
you may not be interested in.

### Implications for end-users - Phoenix.LiveView.attach_hook/4 (function)

Allowing a hook to halt the invocation of the callback means that you can
attach hooks to intercept specific events before detaching themselves,
while allowing other events to continue normally.

### Replying to events - Phoenix.LiveView.attach_hook/4 (function)

Hooks attached to the `:handle_event` stage are able to reply to client events
by returning `{:halt, reply, socket}`. This is useful especially for [JavaScript
interoperability](js-interop.html#client-hooks-via-phx-hook) because a client hook
can push an event and receive a reply.

### Sharing event handling logic - Phoenix.LiveView.attach_hook/4 (function)

Lifecycle hooks are an excellent way to extract related events out of the parent LiveView and
into separate modules without resorting unnecessarily to LiveComponents for organization.

    defmodule DemoLive do
      use Phoenix.LiveView

      def render(assigns) do
        ~H"""
         
           
            Counter: {@counter}
             + 
           

           
         
        """
      end

      def mount(_params, _session, socket) do
        first_list = for(i <- 1..9, do: "First List #{i}") |> Enum.shuffle()
        second_list = for(i <- 1..9, do: "Second List #{i}") |> Enum.shuffle()

        socket =
          socket
          |> assign(:counter, 0)
          |> assign(first_list: first_list)
          |> assign(second_list: second_list)
          |> attach_hook(:sort, :handle_event, &MySortComponent.hooked_event/3)  # 2) Delegated events
        {:ok, socket}
      end

      # 1) Normal event
      def handle_event("inc", _params, socket) do
        {:noreply, update(socket, :counter, &(&1 + 1))}
      end
    end

    defmodule MySortComponent do
      use Phoenix.Component

      def display(assigns) do
        ~H"""
         
            {item}  
           Shuffle 
           Sort 
         
        """
      end

      def hooked_event("shuffle", %{"list" => key}, socket) do
        key = String.to_existing_atom(key)
        shuffled = Enum.shuffle(socket.assigns[key])

        {:halt, assign(socket, key, shuffled)}
      end

      def hooked_event("sort", %{"list" => key}, socket) do
        key = String.to_existing_atom(key)
        sorted = Enum.sort(socket.assigns[key])

        {:halt, assign(socket, key, sorted)}
      end

      def hooked_event(_event, _params, socket), do: {:cont, socket}
    end

### Other examples - Phoenix.LiveView.attach_hook/4 (function)

Attaching and detaching a hook:

    def mount(_params, _session, socket) do
      socket =
        attach_hook(socket, :my_hook, :handle_event, fn
          "very-special-event", _params, socket ->
            # Handle the very special event and then detach the hook
            {:halt, detach_hook(socket, :my_hook, :handle_event)}

          _event, _params, socket ->
            {:cont, socket}
        end)

      {:ok, socket}
    end

Replying to a client event:

```javascript
/**
 * @type {import("phoenix_live_view").HooksOption}
 */
let Hooks = {}
Hooks.ClientHook = {
  mounted() {
    this.pushEvent("ClientHook:mounted", {hello: "world"}, (reply) => {
      console.log("received reply:", reply)
    })
  }
}
let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, ...})
```

    def render(assigns) do
      ~H"""
        
      """
    end

    def mount(_params, _session, socket) do
      socket =
        attach_hook(socket, :reply_on_client_hook_mounted, :handle_event, fn
          "ClientHook:mounted", params, socket ->
            {:halt, params, socket}

          _, _, socket ->
            {:cont, socket}
        end)

      {:ok, socket}
    end

### Phoenix.LiveView.cancel_async/3 (function)

Cancels an async operation if one exists.

Accepts either the `%AsyncResult{}` when using `assign_async/3` or
the key passed to `start_async/3`.

The underlying process will be killed with the provided reason, or
with `{:shutdown, :cancel}` if no reason is passed. For `assign_async/3`
operations, the `:failed` field will be set to `{:exit, reason}`.
For `start_async/3`, the `c:handle_async/3` callback will receive
`{:exit, reason}` as the result.

Returns the `%Phoenix.LiveView.Socket{}`.

### Examples - Phoenix.LiveView.cancel_async/3 (function)

cancel_async(socket, :preview)
    cancel_async(socket, :preview, :my_reason)
    cancel_async(socket, socket.assigns.preview)

### Phoenix.LiveView.cancel_upload/3 (function)

Cancels an upload for the given entry.

### Examples - Phoenix.LiveView.cancel_upload/3 (function)

```heex
<%= for entry <- @uploads.avatar.entries do %>
  ...
   cancel 
<% end %>
```

    def handle_event("cancel-upload", %{"ref" => ref}, socket) do
      {:noreply, cancel_upload(socket, :avatar, ref)}
    end

### Phoenix.LiveView.clear_flash/1 (function)

Clears the flash.

### Examples - Phoenix.LiveView.clear_flash/1 (function)

iex> clear_flash(socket)

Clearing the flash can also be triggered on the client and natively handled by LiveView using the `lv:clear-flash` event.

For example:

```heex
 
  {Phoenix.Flash.get(@flash, :info)}
 
```

### Phoenix.LiveView.clear_flash/2 (function)

Clears a key from the flash.

### Examples - Phoenix.LiveView.clear_flash/2 (function)

iex> clear_flash(socket, :info)

Clearing the flash can also be triggered on the client and natively handled by LiveView using the `lv:clear-flash` event.

For example:

```heex
 
  {Phoenix.Flash.get(@flash, :info)}
 
```

### Phoenix.LiveView.connected?/1 (function)

Returns true if the socket is connected.

Useful for checking the connectivity status when mounting the view.
For example, on initial page render, the view is mounted statically,
rendered, and the HTML is sent to the client. Once the client
connects to the server, a LiveView is then spawned and mounted
statefully within a process. Use `connected?/1` to conditionally
perform stateful work, such as subscribing to pubsub topics,
sending messages, etc.

### Examples - Phoenix.LiveView.connected?/1 (function)

defmodule DemoWeb.ClockLive do
      use Phoenix.LiveView
      ...
      def mount(_params, _session, socket) do
        if connected?(socket), do: :timer.send_interval(1000, self(), :tick)

        {:ok, assign(socket, date: :calendar.local_time())}
      end

      def handle_info(:tick, socket) do
        {:noreply, assign(socket, date: :calendar.local_time())}
      end
    end

### Phoenix.LiveView.consume_uploaded_entries/3 (function)

Consumes the uploaded entries.

Raises when there are still entries in progress.
Typically called when submitting a form to handle the
uploaded entries alongside the form data. For form submissions,
it is guaranteed that all entries have completed before the submit event
is invoked. Once entries are consumed, they are removed from the upload.

The function passed to consume may return a tagged tuple of the form
`{:ok, my_result}` to collect results about the consumed entries, or
`{:postpone, my_result}` to collect results, but postpone the file
consumption to be performed later.

A list of all `my_result` values produced by the passed function is
returned, regardless of whether they were consumed or postponed.

### Examples - Phoenix.LiveView.consume_uploaded_entries/3 (function)

def handle_event("save", _params, socket) do
      uploaded_files =
        consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry ->
          dest = Path.join("priv/static/uploads", Path.basename(path))
          File.cp!(path, dest)
          {:ok, ~p"/uploads/#{Path.basename(dest)}"}
        end)
      {:noreply, update(socket, :uploaded_files, &(&1 ++ uploaded_files))}
    end

### Phoenix.LiveView.consume_uploaded_entry/3 (function)

Consumes an individual uploaded entry.

Raises when the entry is still in progress.
Typically called when submitting a form to handle the
uploaded entries alongside the form data. Once entries are consumed,
they are removed from the upload.

This is a lower-level feature than `consume_uploaded_entries/3` and useful
for scenarios where you want to consume entries as they are individually completed.

Like `consume_uploaded_entries/3`, the function passed to consume may return
a tagged tuple of the form `{:ok, my_result}` to collect results about the
consumed entries, or `{:postpone, my_result}` to collect results,
but postpone the file consumption to be performed later.

### Examples - Phoenix.LiveView.consume_uploaded_entry/3 (function)

def handle_event("save", _params, socket) do
      case uploaded_entries(socket, :avatar) do
        {[_|_] = entries, []} ->
          uploaded_files = for entry <- entries do
            consume_uploaded_entry(socket, entry, fn %{path: path} ->
              dest = Path.join("priv/static/uploads", Path.basename(path))
              File.cp!(path, dest)
              {:ok, ~p"/uploads/#{Path.basename(dest)}"}
            end)
          end
          {:noreply, update(socket, :uploaded_files, &(&1 ++ uploaded_files))}

        _ ->
          {:noreply, socket}
      end
    end

### Phoenix.LiveView.detach_hook/3 (function)

Detaches a hook with the given `name` from the lifecycle `stage`.

> Note: This function is for server-side lifecycle callbacks.
> For client-side hooks, see the
> [JS Interop guide](js-interop.html#client-hooks-via-phx-hook).

If no hook is found, this function is a no-op.

### Examples - Phoenix.LiveView.detach_hook/3 (function)

def handle_event(_, socket) do
      {:noreply, detach_hook(socket, :hook_that_was_attached, :handle_event)}
    end

### Phoenix.LiveView.disallow_upload/2 (function)

Revokes a previously allowed upload from `allow_upload/3`.

### Examples - Phoenix.LiveView.disallow_upload/2 (function)

disallow_upload(socket, :avatar)

### Phoenix.LiveView.get_connect_info/2 (function)

Accesses a given connect info key from the socket.

The following keys are supported: `:peer_data`, `:trace_context_headers`,
`:x_headers`, `:uri`, and `:user_agent`.

The connect information is available only during mount. During disconnected
render, all keys are available. On connected render, only the keys explicitly
declared in your socket are available. See `Phoenix.Endpoint.socket/3` for
a complete description of the keys.

### Examples - Phoenix.LiveView.get_connect_info/2 (function)

The first step is to declare the `connect_info` you want to receive.
Typically, it includes at least the session, but you must include all
other keys you want to access on connected mount, such as `:peer_data`:

    socket "/live", Phoenix.LiveView.Socket,
      websocket: [connect_info: [:peer_data, session: @session_options]]

Those values can now be accessed on the connected mount as
`get_connect_info/2`:

    def mount(_params, _session, socket) do
      peer_data = get_connect_info(socket, :peer_data)
      {:ok, assign(socket, ip: peer_data.address)}
    end

If the key is not available, usually because it was not specified
in `connect_info`, it returns nil.

### Phoenix.LiveView.get_connect_params/1 (function)

Accesses the connect params sent by the client for use on connected mount.

Connect params are sent from the client on every connection and reconnection.
The parameters in the client can be computed dynamically, allowing you to pass
client state to the server. For example, you could use it to compute and pass
the user time zone from a JavaScript client:

```javascript
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: (_liveViewName) => {
    return {
      _csrf_token: csrfToken,
      time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone
    }
  }
})
```

By computing the parameters with a function, reconnections will reevalute
the code, allowing you to fetch the latest data.

On the LiveView, you will use `get_connect_params/1` to read the data,
which only remains available during mount. `nil` is returned when called
in a disconnected state and a `RuntimeError` is raised if called after
mount.

### Reserved params - Phoenix.LiveView.get_connect_params/1 (function)

The following params have special meaning in LiveView:

  * `"_csrf_token"` - the CSRF Token which must be explicitly set by the user
    when connecting
  * `"_mounts"` - the number of times the current LiveView is mounted.
    It is 0 on first mount, then increases on each reconnect. It resets
    when navigating away from the current LiveView or on errors
  * `"_track_static"` - set automatically with a list of all href/src from
    tags with the `phx-track-static` annotation in them. If there are no
    such tags, nothing is sent
  * `"_live_referer"` - sent by the client as the referer URL when a
    live navigation has occurred from `push_navigate` or client link navigate.

### Examples - Phoenix.LiveView.get_connect_params/1 (function)

def mount(_params, _session, socket) do
      {:ok, assign(socket, width: get_connect_params(socket)["width"] || @width)}
    end

### Phoenix.LiveView.handle_async/3 (callback)

Invoked when the result of an `start_async/3` operation is available.

For a deeper understanding of using this callback,
refer to the ["Arbitrary async operations"](#module-arbitrary-async-operations) section.

### Phoenix.LiveView.handle_call/3 (callback)

Invoked to handle calls from other Elixir processes.

See `GenServer.call/3` and `c:GenServer.handle_call/3`
for more information.

### Phoenix.LiveView.handle_cast/2 (callback)

Invoked to handle casts from other Elixir processes.

See `GenServer.cast/2` and `c:GenServer.handle_cast/2`
for more information. It must always return `{:noreply, socket}`,
where `:noreply` means no additional information is sent
to the process which cast the message.

### Phoenix.LiveView.handle_event/3 (callback)

Invoked to handle events sent by the client.

It receives the `event` name, the event payload as a map,
and the socket.

It must return `{:noreply, socket}`, where `:noreply` means
no additional information is sent to the client, or
`{:reply, map(), socket}`, where the given `map()` is encoded
and sent as a reply to the client.

### Phoenix.LiveView.handle_info/2 (callback)

Invoked to handle messages from other Elixir processes.

See `Kernel.send/2` and `c:GenServer.handle_info/2`
for more information. It must always return `{:noreply, socket}`,
where `:noreply` means no additional information is sent
to the process which sent the message.

### Phoenix.LiveView.handle_params/3 (callback)

Invoked after mount and whenever there is a live patch event.

It receives the current `params`, including parameters from
the router, the current `uri` from the client and the `socket`.
It is invoked after mount or whenever there is a live navigation
event caused by `push_patch/2` or `<.link patch={...}>`.

It must always return `{:noreply, socket}`, where `:noreply`
means no additional information is sent to the client.

> #### Note {: .warning}
>
> `handle_params` is only allowed on LiveViews mounted at the router,
> as it takes the current url of the page as the second parameter.

### Phoenix.LiveView.mount/3 (callback)

The LiveView entry-point.

For each LiveView in the root of a template, `c:mount/3` is invoked twice:
once to do the initial page load and again to establish the live socket.

It expects three arguments:

  * `params` - a map of string keys which contain public information that
    can be set by the user. The map contains the query params as well as any
    router path parameter. If the LiveView was not mounted at the router,
    this argument is the atom `:not_mounted_at_router`
  * `session` - the connection session
  * `socket` - the LiveView socket

It must return either `{:ok, socket}` or `{:ok, socket, options}`, where
`options` is one of:

  * `:temporary_assigns` - a keyword list of assigns that are temporary
    and must be reset to their value after every render. Note that once
    the value is reset, it won't be re-rendered again until it is explicitly
    assigned

  * `:layout` - the optional layout to be used by the LiveView. Setting
    this option will override any layout previously set via
    `Phoenix.LiveView.Router.live_session/2` or on `use Phoenix.LiveView`

### Phoenix.LiveView.on_mount/1 (macro)

Declares a module callback to be invoked on the LiveView's mount.

The function within the given module, which must be named `on_mount`,
will be invoked before both disconnected and connected mounts. The hook
has the option to either halt or continue the mounting process as usual.
If you wish to redirect the LiveView, you **must** halt, otherwise an error
will be raised.

Tip: if you need to define multiple `on_mount` callbacks, avoid defining
multiple modules. Instead, pass a tuple and use pattern matching to handle
different cases:

    def on_mount(:admin, _params, _session, socket) do
      {:cont, socket}
    end

    def on_mount(:user, _params, _session, socket) do
      {:cont, socket}
    end

And then invoke it as:

    on_mount {MyAppWeb.SomeHook, :admin}
    on_mount {MyAppWeb.SomeHook, :user}

Registering `on_mount` hooks can be useful to perform authentication
as well as add custom behaviour to other callbacks via `attach_hook/4`.

The `on_mount` callback can return a keyword list of options as a third
element in the return tuple. These options are identical to what can
optionally be returned in `c:mount/3`.

### Examples - Phoenix.LiveView.on_mount/1 (macro)

The following is an example of attaching a hook via
`Phoenix.LiveView.Router.live_session/3`:

    # lib/my_app_web/live/init_assigns.ex
    defmodule MyAppWeb.InitAssigns do
      @moduledoc """
      Ensures common `assigns` are applied to all LiveViews attaching this hook.
      """
      import Phoenix.LiveView
      import Phoenix.Component

      def on_mount(:default, _params, _session, socket) do
        {:cont, assign(socket, :page_title, "DemoWeb")}
      end

      def on_mount(:user, params, session, socket) do
        # code
      end

      def on_mount(:admin, _params, _session, socket) do
        {:cont, socket, layout: {DemoWeb.Layouts, :admin}}
      end
    end

    # lib/my_app_web/router.ex
    defmodule MyAppWeb.Router do
      use MyAppWeb, :router

      # pipelines, plugs, etc.

      live_session :default, on_mount: MyAppWeb.InitAssigns do
        scope "/", MyAppWeb do
          pipe_through :browser
          live "/", PageLive, :index
        end
      end

      live_session :authenticated, on_mount: {MyAppWeb.InitAssigns, :user} do
        scope "/", MyAppWeb do
          pipe_through [:browser, :require_user]
          live "/profile", UserLive.Profile, :index
        end
      end

      live_session :admins, on_mount: {MyAppWeb.InitAssigns, :admin} do
        scope "/admin", MyAppWeb.Admin do
          pipe_through [:browser, :require_user, :require_admin]
          live "/", AdminLive.Index, :index
        end
      end
    end

### Phoenix.LiveView.push_event/3 (function)

Pushes an event to the client.

Events can be handled in two ways:

  1. They can be handled on `window` via `addEventListener`.
     A "phx:" prefix will be added to the event name.

  2. They can be handled inside a hook via `handleEvent`.

Events are dispatched to all active hooks on the client who are
handling the given `event`. If you need to scope events, then
this must be done by namespacing them.

Events pushed during `push_navigate` are currently discarded,
as the LiveView is immediately dismounted.

### Hook example - Phoenix.LiveView.push_event/3 (function)

If you push a "scores" event from your LiveView:

    {:noreply, push_event(socket, "scores", %{points: 100, user: "josé"})}

A hook declared via `phx-hook` can handle it via `handleEvent`:

```javascript
this.handleEvent("scores", data => ...)
```

## `window` example

All events are also dispatched on the `window`. This means you can handle
them by adding listeners. For example, if you want to remove an element
from the page, you can do this:

    {:noreply, push_event(socket, "remove-el", %{id: "foo-bar"})}

And now in your app.js you can register and handle it:

```javascript
window.addEventListener(
  "phx:remove-el",
  e => document.getElementById(e.detail.id).remove()
)
```

### Phoenix.LiveView.push_navigate/2 (function)

Annotates the socket for navigation to another LiveView in the same `live_session`.

The current LiveView will be shutdown and a new one will be mounted
in its place, without reloading the whole page. This can
also be used to remount the same LiveView, in case you want to start
fresh. If you want to navigate to the same LiveView without remounting
it, use `push_patch/2` instead.

### Options - Phoenix.LiveView.push_navigate/2 (function)

* `:to` - the required path to link to. It must always be a local path
  * `:replace` - the flag to replace the current history or push a new state.
    Defaults `false`.

### Examples - Phoenix.LiveView.push_navigate/2 (function)

{:noreply, push_navigate(socket, to: "/")}
    {:noreply, push_navigate(socket, to: "/", replace: true)}

### Phoenix.LiveView.push_patch/2 (function)

Annotates the socket for navigation within the current LiveView.

When navigating to the current LiveView, `c:handle_params/3` is
immediately invoked to handle the change of params and URL state.
Then the new state is pushed to the client, without reloading the
whole page while also maintaining the current scroll position.
For live navigation to another LiveView in the same `live_session`,
use `push_navigate/2`. Otherwise, use `redirect/2`.

### Options - Phoenix.LiveView.push_patch/2 (function)

* `:to` - the required path to link to. It must always be a local path
  * `:replace` - the flag to replace the current history or push a new state.
    Defaults `false`.

### Examples - Phoenix.LiveView.push_patch/2 (function)

{:noreply, push_patch(socket, to: "/")}
    {:noreply, push_patch(socket, to: "/", replace: true)}

### Phoenix.LiveView.put_flash/3 (function)

Adds a flash message to the socket to be displayed.

The flash message will stick around until it is read.
If you perform a redirect or a navigation event, the message will be
signed and temporarily stored in the client. Therefore it is important
to use flash messages only for user-facing notifications. Do not store
sensitive information in flash messages.

In a typical LiveView application, the message will be rendered by the
CoreComponents’ `flash/1` component. It is up to this function to determine
what kind of messages it supports. By default, the `:info` and `:error`
kinds are handled.

*Note*: You must also place the `Phoenix.LiveView.Router.fetch_live_flash/2`
plug in your browser's pipeline in place of `fetch_flash` for LiveView flash
messages be supported, for example:

    import Phoenix.LiveView.Router

    pipeline :browser do
      ...
      plug :fetch_live_flash
    end

### Examples - Phoenix.LiveView.put_flash/3 (function)

iex> put_flash(socket, :info, "It worked!")
    iex> put_flash(socket, :error, "You can't access that page")

### Inside components - Phoenix.LiveView.put_flash/3 (function)

You can use `put_flash/3` inside a `Phoenix.LiveComponent` and
components have their own `@flash` assigns. The `@flash` assign
in a component is only copied to its parent LiveView if the component
calls `push_navigate/2` or `push_patch/2`.

### Phoenix.LiveView.put_private/3 (function)

Puts a new private key and value in the socket.

Privates are *not change tracked*. This storage is meant to be used by
users and libraries to hold state that doesn't require
change tracking. The keys should be prefixed with the app/library name.

### Examples - Phoenix.LiveView.put_private/3 (function)

Key values can be placed in private:

    put_private(socket, :myapp_meta, %{foo: "bar"})

And then retrieved:

    socket.private[:myapp_meta]

### Phoenix.LiveView.redirect/2 (function)

Annotates the socket for redirect to a destination path.

*Note*: LiveView redirects rely on instructing client
to perform a `window.location` update on the provided
redirect location. The whole page will be reloaded and
all state will be discarded.

### Options - Phoenix.LiveView.redirect/2 (function)

* `:to` - the path to redirect to. It must always be a local path
  * `:status` - the HTTP status code to use for the redirect. Defaults to 302.
  * `:external` - an external path to redirect to. Either a string
    or `{scheme, url}` to redirect to a custom scheme

### Examples - Phoenix.LiveView.redirect/2 (function)

{:noreply, redirect(socket, to: "/")}
    {:noreply, redirect(socket, to: "/", status: 301)}
    {:noreply, redirect(socket, external: "https://example.com")}

### Phoenix.LiveView.render/1 (callback)

Renders a template.

This callback is invoked whenever LiveView detects
new content must be rendered and sent to the client.

If you define this function, it must return a template
defined via the `Phoenix.Component.sigil_H/2`.

If you don't define this function, LiveView will attempt
to render a template in the same directory as your LiveView.
For example, if you have a LiveView named `MyApp.MyCustomView`
inside `lib/my_app/live_views/my_custom_view.ex`, Phoenix
will look for a template at `lib/my_app/live_views/my_custom_view.html.heex`.

### Phoenix.LiveView.render_with/2 (function)

Configures which function to use to render a LiveView/LiveComponent.

By default, LiveView invokes the `render/1` function in the same module
the LiveView/LiveComponent is defined, passing `assigns` as its sole
argument. This function allows you to set a different rendering function.

One possible use case for this function is to set a different template
on disconnected render. When the user first accesses a LiveView, we will
perform a disconnected render to send to the browser. This is useful for
several reasons, such as reducing the time to first paint and for search
engine indexing.

However, when LiveView is gated behind an authentication page, it may be
useful to render a placeholder on disconnected render and perform the
full render once the WebSocket connects. This can be achieved with
`render_with/2` and is particularly useful on complex pages (such as
dashboards and reports).

To do so, you must simply invoke `render_with(socket, &some_function_component/1)`,
configuring your socket with a new rendering function.

### Phoenix.LiveView.send_update/3 (function)

Asynchronously updates a `Phoenix.LiveComponent` with new assigns.

The `pid` argument is optional and it defaults to the current process,
which means the update instruction will be sent to a component running
on the same LiveView. If the current process is not a LiveView or you
want to send updates to a live component running on another LiveView,
you should explicitly pass the LiveView's pid instead.

The second argument can be either the value of the `@myself` or the module of
the live component. If you pass the module, then the `:id` that identifies
the component must be passed as part of the assigns.

When the component receives the update,
[`update_many/1`](`c:Phoenix.LiveComponent.update_many/1`) will be invoked if
it is defined, otherwise [`update/2`](`c:Phoenix.LiveComponent.update/2`) is
invoked with the new assigns.  If
[`update/2`](`c:Phoenix.LiveComponent.update/2`) is not defined all assigns
are simply merged into the socket. The assigns received as the first argument
of the [`update/2`](`c:Phoenix.LiveComponent.update/2`) callback will only
include the _new_ assigns passed from this function.  Pre-existing assigns may
be found in `socket.assigns`.

While a component may always be updated from the parent by updating some
parent assigns which will re-render the child, thus invoking
[`update/2`](`c:Phoenix.LiveComponent.update/2`) on the child component,
`send_update/3` is useful for updating a component that entirely manages its
own state, as well as messaging between components mounted in the same
LiveView.

### Examples - Phoenix.LiveView.send_update/3 (function)

def handle_event("cancel-order", _, socket) do
      ...
      send_update(Cart, id: "cart", status: "cancelled")
      {:noreply, socket}
    end

    def handle_event("cancel-order-asynchronously", _, socket) do
      ...
      pid = self()

      Task.Supervisor.start_child(MyTaskSup, fn ->
        # Do something asynchronously
        send_update(pid, Cart, id: "cart", status: "cancelled")
      end)

      {:noreply, socket}
    end

    def render(assigns) do
      ~H"""
      <.some_component on_complete={&send_update(@myself, completed: &1)} />
      """
    end

### Phoenix.LiveView.send_update_after/4 (function)

Similar to `send_update/3` but the update will be delayed according to the given `time_in_milliseconds`.

It returns a reference which can be cancelled with `Process.cancel_timer/1`.

### Examples - Phoenix.LiveView.send_update_after/4 (function)

def handle_event("cancel-order", _, socket) do
      ...
      send_update_after(Cart, [id: "cart", status: "cancelled"], 3000)
      {:noreply, socket}
    end

    def handle_event("cancel-order-asynchronously", _, socket) do
      ...
      pid = self()

      Task.start(fn ->
        # Do something asynchronously
        send_update_after(pid, Cart, [id: "cart", status: "cancelled"], 3000)
      end)

      {:noreply, socket}
    end

### Phoenix.LiveView.start_async/4 (macro)

Wraps your function in an asynchronous task and invokes a callback `name` to
handle the result.

The task is linked to the caller and errors/exits are wrapped.
The result of the task is sent to the `c:handle_async/3` callback
of the caller LiveView or LiveComponent.

If there is an in-flight task with the same `name`, the later `start_async` wins and the previous task’s result is ignored.
If you wish to replace an existing task, you can use `cancel_async/3` before `start_async/3`.
You are not restricted to just atoms for `name`, it can be any term such as a tuple.

The task is only started when the socket is connected.

### Options - Phoenix.LiveView.start_async/4 (macro)

* `:supervisor` - allows you to specify a `Task.Supervisor` to supervise the task.

### Examples - Phoenix.LiveView.start_async/4 (macro)

def mount(%{"id" => id}, _, socket) do
      {:ok,
       socket
       |> assign(:org, AsyncResult.loading())
       |> start_async(:my_task, fn -> fetch_org!(id) end)}
    end

    def handle_async(:my_task, {:ok, fetched_org}, socket) do
      %{org: org} = socket.assigns
      {:noreply, assign(socket, :org, AsyncResult.ok(org, fetched_org))}
    end

    def handle_async(:my_task, {:exit, reason}, socket) do
      %{org: org} = socket.assigns
      {:noreply, assign(socket, :org, AsyncResult.failed(org, {:exit, reason}))}
    end

See the moduledoc for more information.

### Phoenix.LiveView.static_changed?/1 (function)

Returns true if the socket is connected and the tracked static assets have changed.

This function is useful to detect if the client is running on an outdated
version of the marked static files. It works by comparing the static paths
sent by the client with the one on the server.

**Note:** this functionality requires Phoenix v1.5.2 or later.

To use this functionality, the first step is to annotate which static files
you want to be tracked by LiveView, with the `phx-track-static`. For example:

```heex
 
  
```

Now, whenever LiveView connects to the server, it will send a copy `src`
or `href` attributes of all tracked statics and compare those values with
the latest entries computed by `mix phx.digest` in the server.

The tracked statics on the client will match the ones on the server the
huge majority of times. However, if there is a new deployment, those values
may differ. You can use this function to detect those cases and show a
banner to the user, asking them to reload the page. To do so, first set the
assign on mount:

    def mount(params, session, socket) do
      {:ok, assign(socket, static_changed?: static_changed?(socket))}
    end

And then in your views:

```heex
 
  The app has been updated. Click here to  reload .
 
```

If you prefer, you can also send a JavaScript script that immediately
reloads the page.

**Note:** only set `phx-track-static` on your own assets. For example, do
not set it in external JavaScript files:

```heex
  
```

Because you don't actually serve the file above, LiveView will interpret
the static above as missing, and this function will return true.

### Phoenix.LiveView.stream/4 (function)

Assigns a new stream to the socket or inserts items into an existing stream.
Returns an updated `socket`.

Streams are a mechanism for managing large collections on the client without
keeping the resources on the server.

  * `name` - A string or atom name of the key to place under the
    `@streams` assign.
  * `items` - An enumerable of items to insert.

The following options are supported:

  * `:at` - The index to insert or update the items in the
    collection on the client. By default `-1` is used, which appends the items
    to the parent DOM container. A value of `0` prepends the items.

    Note that this operation is equal to inserting the items one by one, each at
    the given index. Therefore, when inserting multiple items at an index other than `-1`,
    the UI will display the items in reverse order:

        stream(socket, :songs, [song1, song2, song3], at: 0)

    In this case the UI will prepend `song1`, then `song2` and then `song3`, so it will show
    `song3`, `song2`, `song1` and then any previously inserted items.

    To insert in the order of the list, use `Enum.reverse/1`:

        stream(socket, :songs, Enum.reverse([song1, song2, song3]), at: 0)

  * `:reset` - A boolean to reset the stream on the client or not. Defaults
    to `false`.

  * `:limit` - An optional positive or negative number of results to limit
    on the UI on the client. As new items are streamed, the UI will remove existing
    items to maintain the limit. For example, to limit the stream to the last 10 items
    in the UI while appending new items, pass a negative value:

        stream(socket, :songs, songs, at: -1, limit: -10)

    Likewise, to limit the stream to the first 10 items, while prepending new items,
    pass a positive value:

        stream(socket, :songs, songs, at: 0, limit: 10)

Once a stream is defined, a new `@streams` assign is available containing
the name of the defined streams. For example, in the above definition, the
stream may be referenced as `@streams.songs` in your template. Stream items
are temporary and freed from socket state immediately after the `render/1`
function is invoked (or a template is rendered from disk).

By default, calling `stream/4` on an existing stream will bulk insert the new items
on the client while leaving the existing items in place. Streams may also be reset
when calling `stream/4`, which we discuss below.

### Resetting a stream - Phoenix.LiveView.stream/4 (function)

To empty a stream container on the client, you can pass `:reset` with an empty list:

    stream(socket, :songs, [], reset: true)

Or you can replace the entire stream on the client with a new collection:

    stream(socket, :songs, new_songs, reset: true)

### Limiting a stream - Phoenix.LiveView.stream/4 (function)

It is often useful to limit the number of items in the UI while allowing the
server to stream new items in a fire-and-forget fashion. This prevents
the server from overwhelming the client with new results while also opening up
powerful features like virtualized infinite scrolling. See a complete
bidirectional infinite scrolling example with stream limits in the
[scroll events guide](bindings.md#scroll-events-and-infinite-pagination)

When a stream exceeds the limit on the client, the existing items will be pruned
based on the number of items in the stream container and the limit direction. A
positive limit will prune items from the end of the container, while a negative
limit will prune items from the beginning of the container.

Note that the limit is not enforced on the first `c:mount/3` render (when no websocket
connection was established yet), as it means more data than necessary has been
loaded. In such cases, you should only load and pass the desired amount of items
to the stream.

When inserting single items using `stream_insert/4`, the limit needs to be passed
as an option for it to be enforced on the client:

    stream_insert(socket, :songs, song, limit: -10)

### Required DOM attributes - Phoenix.LiveView.stream/4 (function)

For stream items to be trackable on the client, the following requirements
must be met:

  1. The parent DOM container must include a `phx-update="stream"` attribute,
     along with a unique DOM id.
  2. Each stream item must include its DOM id on the item's element.

> #### Note {: .warning}
>
> Failing to place `phx-update="stream"` on the **immediate parent** for
> **each stream** will result in broken behavior.
>
> Also, do not alter the generated DOM ids, e.g., by prefixing them. Doing so will
> result in broken behavior.

When consuming a stream in a template, the DOM id and item is passed as a tuple,
allowing convenient inclusion of the DOM id for each item. For example:

```heex
 
   
     
       {song.title} 
       {song.duration} 
     
   
 
```

We consume the stream in a for comprehension by referencing the
`@streams.songs` assign. We used the computed DOM id to populate
the ` ` id, then we render the table row as usual.

Now `stream_insert/3` and `stream_delete/3` may be issued and new rows will
be inserted or deleted from the client.

### Handling the empty case - Phoenix.LiveView.stream/4 (function)

When rendering a list of items, it is common to show a message for the empty case.
But when using streams, we cannot rely on `Enum.empty?/1` or similar approaches to
check if the list is empty. Instead we can use the CSS `:only-child` selector
and show the message client side:

```heex
 
   
     
       No songs found 
     
     
       {song.title} 
       {song.duration} 
     
   
 
```

It is important to set a unique ID on the empty row, otherwise it cannot be tracked
in the stream container and subsequent patches will duplicate the node.

### Non-stream items in stream containers - Phoenix.LiveView.stream/4 (function)

In the section on handling the empty case, we showed how to render a message when
the stream is empty by rendering a non-stream item inside the stream container.

Note that for non-stream items inside a `phx-update="stream"` container, the following
needs to be considered:

  1. Non-stream items must have a unique DOM id.

  2. Items can be added and updated, but not removed, even if the stream is reset.

     This means that if you try to conditionally render a non-stream item inside a stream container,
     it won't be removed if it was rendered once.

  3. Items are affected by the `:at` option.

     For example, when you render a non-stream item at the beginning of the stream container and then
     prepend items (with `at: 0`) to the stream, the non-stream item will be pushed down.

### Phoenix.LiveView.stream_configure/3 (function)

Configures a stream.

The following options are supported:

  * `:dom_id` - An optional function to generate each stream item's DOM id.
    The function accepts each stream item and converts the item to a string id.
    By default, the `:id` field of a map or struct will be used if the item has
    such a field, and will be prefixed by the `name` hyphenated with the id.
    For example, the following examples are equivalent:

        stream(socket, :songs, songs)

        socket
        |> stream_configure(:songs, dom_id: &("songs-#{&1.id}"))
        |> stream(:songs, songs)

A stream must be configured before items are inserted, and once configured,
a stream may not be re-configured. To ensure a stream is only configured a
single time in a LiveComponent, use the `mount/1` callback. For example:

    def mount(socket) do
      {:ok, stream_configure(socket, :songs, dom_id: &("songs-#{&1.id}"))}
    end

    def update(assigns, socket) do
      {:ok, stream(socket, :songs, ...)}
    end

Returns an updated `socket`.

### Phoenix.LiveView.stream_delete/3 (function)

Deletes an item from the stream.

The item's DOM is computed from the `:dom_id` provided in the `stream/3` definition.
Delete information for this DOM id is sent to the client and the item's element
is removed from the DOM, following the same behavior of element removal, such as
invoking `phx-remove` commands and executing client hook `destroyed()` callbacks.

### Examples - Phoenix.LiveView.stream_delete/3 (function)

def handle_event("delete", %{"id" => id}, socket) do
      song = get_song!(id)
      {:noreply, stream_delete(socket, :songs, song)}
    end

See `stream_delete_by_dom_id/3` to remove an item without requiring the
original data structure.

Returns an updated `socket`.

### Phoenix.LiveView.stream_delete_by_dom_id/3 (function)

Deletes an item from the stream given its computed DOM id.

Returns an updated `socket`.

Behaves just like `stream_delete/3`, but accept the precomputed DOM id,
which allows deleting from a stream without fetching or building the original
stream data structure.

### Examples - Phoenix.LiveView.stream_delete_by_dom_id/3 (function)

def render(assigns) do
      ~H"""
       
         
           
             {song.title} 
              delete  
           
         
       
      """
    end

    def handle_event("delete", %{"id" => dom_id}, socket) do
      {:noreply, stream_delete_by_dom_id(socket, :songs, dom_id)}
    end

### Phoenix.LiveView.stream_insert/4 (function)

Inserts a new item or updates an existing item in the stream.

Returns an updated `socket`.

See `stream/4` for inserting multiple items at once.

The following options are supported:

  * `:at` - The index to insert or update the item in the collection on the client.
    By default, the item is appended to the parent DOM container. This is the same as
    passing a value of `-1`.
    If the item already exists in the parent DOM container then it will be
    updated in place.

  * `:limit` - A limit of items to maintain in the UI. A limit passed to `stream/4` does
    not affect subsequent calls to `stream_insert/4`, therefore the limit must be passed
    here as well in order to be enforced. See `stream/4` for more information on
    limiting streams.

  * `:update_only` - A boolean to only update the item in the stream. If the item does not
    exist on the client, it will not be inserted. Defaults to `false`.

### Examples - Phoenix.LiveView.stream_insert/4 (function)

Imagine you define a stream on mount with a single item:

    stream(socket, :songs, [%Song{id: 1, title: "Song 1"}])

Then, in a callback such as `handle_info` or `handle_event`, you
can append a new song:

    stream_insert(socket, :songs, %Song{id: 2, title: "Song 2"})

Or prepend a new song with `at: 0`:

    stream_insert(socket, :songs, %Song{id: 2, title: "Song 2"}, at: 0)

Or update an existing song (in this case the `:at` option has no effect):

    stream_insert(socket, :songs, %Song{id: 1, title: "Song 1 updated"}, at: 0)

Or append a new song while limiting the stream to the last 10 items:

    stream_insert(socket, :songs, %Song{id: 2, title: "Song 2"}, limit: -10)

### Updating Items - Phoenix.LiveView.stream_insert/4 (function)

As shown, an existing item on the client can be updated by issuing a `stream_insert`
for the existing item. When the client updates an existing item, the item will remain
in the same location as it was previously, and will not be moved to the end of the
parent children. To both update an existing item and move it to another position,
issue a `stream_delete`, followed by a `stream_insert`. For example:

    song = get_song!(id)

    socket
    |> stream_delete(:songs, song)
    |> stream_insert(:songs, song, at: -1)

See `stream_delete/3` for more information on deleting items.

### Phoenix.LiveView.terminate/2 (callback)

Invoked when the LiveView is terminating.

In case of errors, this callback is only invoked if the LiveView
is trapping exits. See `c:GenServer.terminate/2` for more info.

### Phoenix.LiveView.transport_pid/1 (function)

Returns the transport pid of the socket.

Raises `ArgumentError` if the socket is not connected.

### Examples - Phoenix.LiveView.transport_pid/1 (function)

iex> transport_pid(socket)
    #PID<0.107.0>

### Phoenix.LiveView.unsigned_params/0 (type)



### Phoenix.LiveView.uploaded_entries/2 (function)

Returns the completed and in progress entries for the upload.

### Examples - Phoenix.LiveView.uploaded_entries/2 (function)

case uploaded_entries(socket, :photos) do
      {[_ | _] = completed, []} ->
        # all entries are completed

      {[], [_ | _] = in_progress} ->
        # all entries are still in progress
    end

### Phoenix.LiveView.AsyncResult (module)

Provides a data structure for tracking the state of an async assign.

See the `Async Operations` section of the `Phoenix.LiveView` docs for more information.

### Fields - Phoenix.LiveView.AsyncResult (module)

* `:ok?` - When true, indicates the `:result` has been set successfully at least once.
  * `:loading` - The current loading state
  * `:failed` - The current failed state
  * `:result` - The successful result of the async task

### Phoenix.LiveView.AsyncResult.failed/2 (function)

Updates the failed state.

When failed, the loading state will be reset to `nil`.
If the result was previously `ok?`, both `result` and
`failed` will be set.

### Examples - Phoenix.LiveView.AsyncResult.failed/2 (function)

iex> result = AsyncResult.loading()
    iex> result = AsyncResult.failed(result, {:exit, :boom})
    iex> result.failed
    {:exit, :boom}
    iex> result.loading
    nil

### Phoenix.LiveView.AsyncResult.loading/0 (function)

Creates an async result in loading state.

### Examples - Phoenix.LiveView.AsyncResult.loading/0 (function)

iex> result = AsyncResult.loading()
    iex> result.loading
    true
    iex> result.ok?
    false

### Phoenix.LiveView.AsyncResult.loading/1 (function)

Updates the loading state.

When loading, the failed state will be reset to `nil`.

### Examples - Phoenix.LiveView.AsyncResult.loading/1 (function)

iex> result = AsyncResult.loading(%{my: :loading_state})
    iex> result.loading
    %{my: :loading_state}
    iex> result = AsyncResult.loading(result)
    iex> result.loading
    true

### Phoenix.LiveView.AsyncResult.loading/2 (function)

Updates the loading state of an existing `async_result`.

When loading, the failed state will be reset to `nil`.
If the result was previously `ok?`, both `result` and
`loading` will be set.

### Examples - Phoenix.LiveView.AsyncResult.loading/2 (function)

iex> result = AsyncResult.loading()
    iex> result = AsyncResult.loading(result, %{my: :other_state})
    iex> result.loading
    %{my: :other_state}

### Phoenix.LiveView.AsyncResult.ok/1 (function)

Creates a successful result.

The `:ok?` field will also be set to `true` to indicate this result has
completed successfully at least once, regardless of future state changes.

### Examples - Phoenix.LiveView.AsyncResult.ok/1 (function)

iex> result = AsyncResult.ok("initial result")
    iex> result.ok?
    true
    iex> result.result
    "initial result"

### Phoenix.LiveView.AsyncResult.ok/2 (function)

Updates the successful result.

The `:ok?` field will also be set to `true` to indicate this result has
completed successfully at least once, regardless of future state changes.

When ok'd, the loading and failed state will be reset to `nil`.

### Examples - Phoenix.LiveView.AsyncResult.ok/2 (function)

iex> result = AsyncResult.loading()
    iex> result = AsyncResult.ok(result, "completed")
    iex> result.ok?
    true
    iex> result.result
    "completed"
    iex> result.loading
    nil

### Phoenix.LiveView.ColocatedHook (module)

A special HEEx `:type` that extracts [hooks](js-interop.md#client-hooks-via-phx-hook)
from a co-located ` ` tag at compile time.

Note: To use `ColocatedHook`, you need to run Phoenix 1.8+.

### Introduction - Phoenix.LiveView.ColocatedHook (module)

Colocated hooks are defined as with `:type={Phoenix.LiveView.ColocatedHook}`:

    defmodule MyAppWeb.DemoLive do
      use MyAppWeb, :live_view

      def mount(_params, _session, socket) do
        {:ok, socket}
      end

      def render(assigns) do
        ~H"""
         
         
          export default {
            mounted() {
              this.el.addEventListener("input", e => {
                let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
                if(match) {
                  this.el.value = `${match[1]}-${match[2]}-${match[3]}`
                }
              })
            }
          }
         
        """
      end
    end

You can read more about the internals of colocated hooks in the [documentation for colocated JS](`Phoenix.LiveView.ColocatedJS#internals`).
A brief summary: at compile time, the hook's code is extracted into a special folder, typically in your `_build` directory.
Each hook is also `import`ed into a special *manifest* file. The manifest file provides
[a named export](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/export)
which allows it to be imported by any JavaScript bundler that supports [ES modules](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Modules):

```javascript
import {hooks} from "phoenix-colocated/my_app"

console.log(hooks);
/*
{
  "MyAppWeb.DemoLive.PhoneNumber": {...},
  ...
}
*/
```

> #### Compilation order {: .info}
>
> Colocated hooks are only written when the corresponding component is compiled.
> Therefore, whenever you need to access a colocated hook, you need to ensure
> `mix compile` runs first. This automatically happens in development.
>
> If you have a custom mix alias, instead of
>     release: ["assets.deploy", "release"]
> do
>     release: ["compile", "assets.deploy", "release"]
> to ensure that all colocated hooks are extracted before esbuild or any other bundler runs.

### Options - Phoenix.LiveView.ColocatedHook (module)

Colocated hooks are configured through the attributes of the ` ` tag.
The supported attributes are:

  * `name` - The name of the hook. This is required and must start with a dot,
    for example: `name=".myhook"`. The same name must be used when referring to this
    hook in the `phx-hook` attribute of another HTML element.

  * `runtime` - If present, the hook is not extracted, but instead registered at runtime.
    You should only use this option if you know that you need it. It comes with some limitations:

      1. The content is not processed by any bundler, therefore it must only use features
         supported by the targeted browsers.
      2. You need to take special care about any [Content Security Policies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CSP)
         that may be in place. See the section on runtime hooks below for more details.

### Runtime hooks - Phoenix.LiveView.ColocatedHook (module)

Runtime hooks are a special kind of colocated hook that are not removed from the DOM
when rendering the component. Instead, the hook's code is executed directly in the
browser with no bundler involved.

One example where this can be useful is when you are creating a custom page for a library
like `Phoenix.LiveDashboard`. The live dashboard already bundles its hooks, therefore there
is no way to add new hooks to the bundle when the live dashboard is used inside your application.

Because of this, runtime hooks must also use a slightly different syntax. While in normal
colocated hooks you'd write an `export default` statement, runtime hooks must evaluate to the
hook itself:

```heex
 
  {
    mounted() {
      ...
    }
  }
 
```

This is because the hook's code is wrapped by LiveView into something like this:

```javascript
window["phx_hook_HASH"] = function() {
  return {
    mounted() {
      ...
    }
  }
}
```

Still, even for runtime hooks, the hook's name needs to start with a dot and is automatically
prefixed with the module name to avoid conflicts with other hooks.

When using runtime hooks, it is important to think about any limitations that content security
policies may impose. If CSP is involved, the only way to use runtime hooks is by using CSP nonces:

```heex
 
  function() {
    return ...;
  }
 
```

This is assuming that the `@script_csp_nonce` assign contains the nonce value that is also
sent in the `Content-Security-Policy` header.

### Phoenix.LiveView.ColocatedJS (module)

A special HEEx `:type` that extracts any JavaScript code from a co-located
` ` tag at compile time.

Note: To use `ColocatedJS`, you need to run Phoenix 1.8+.

Colocated JavaScript is a more generalized version of `Phoenix.LiveView.ColocatedHook`.
In fact, colocated hooks are built on top of `ColocatedJS`.

You can use `ColocatedJS` to define any JavaScript code (Web Components, global event listeners, etc.)
that do not necessarily need the functionalities of hooks, for example:

```heex
 
  export default class MyWebComponent extends HTMLElement {
    connectedCallback() {
      this.innerHTML = "Hello, world!";
    }
  }
 
```

Then, in your `app.js` file, you could import it like this:

```javascript
import colocated from "phoenix-colocated/my_app";
customElements.define("my-web-component", colocated.MyWebComponent);
```

In this example, you don't actually need to have special code for the web component
inside your `app.js` file, since you could also directly call `customElements.define`
inside the colocated JavaScript. However, this example shows how you can access the
exported values inside your bundle.

> #### A note on dependencies and umbrella projects {: .info}
>
> For each application that uses colocated JavaScript, a separate directory is created
> inside the `phoenix-colocated` folder. This allows to have clear separation between
> hooks and code of dependencies, but also applications inside umbrella projects.
>
> While dependencies would typically still bundle their own hooks and colocated JavaScript
> into a separate file before publishing, simple hooks or code snippets that do not require
> access to third-party libraries can also be directly imported into your own bundle.
> If a library requires this, it should be stated in its documentation.

### Internals - Phoenix.LiveView.ColocatedJS (module)

While compiling the template, colocated JavaScript is extracted into a special folder inside the
`Mix.Project.build_path()`, called `phoenix-colocated`. This is customizable, as we'll see below,
but it is important that it is a directory that is not tracked by version control, because the
components are the source of truth for the code. Also, the directory is shared between applications
(this also applies to applications in umbrella projects), so it should typically also be a shared
directory not specific to a single application.

The colocated JS directory follows this structure:

```text
_build/$MIX_ENV/phoenix-colocated/
_build/$MIX_ENV/phoenix-colocated/my_app/
_build/$MIX_ENV/phoenix-colocated/my_app/index.js
_build/$MIX_ENV/phoenix-colocated/my_app/MyAppWeb.DemoLive/line_HASH.js
_build/$MIX_ENV/phoenix-colocated/my_dependency/MyDependency.Module/line_HASH.js
...
```

Each application has its own folder. Inside, each module also gets its own folder, which allows
us to track and clean up outdated code.

To use colocated JS from your `app.js`, your bundler needs to be configured to resolve the
`phoenix-colocated` folder. For new Phoenix applications, this configuration is already included
in the esbuild configuration inside `config.exs`:

    config :esbuild,
      ...
      my_app: [
        args:
          ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
        cd: Path.expand("../assets", __DIR__),
        env: %{
          "NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]
        }
      ]

The important part here is the `NODE_PATH` environment variable, which tells esbuild to also look
for packages inside the `deps` folder, as well as the `Mix.Project.build_path()`, which resolves to
`_build/$MIX_ENV`. If you use a different bundler, you'll need to configure it accordingly. If it is not
possible to configure the `NODE_PATH`, you can also change the folder to which LiveView writes colocated
JavaScript by setting the `:target_directory` option in your `config.exs`:

```elixir
config :phoenix_live_view, :colocated_js,
  target_directory: Path.expand("../assets/node_modules/phoenix-colocated", __DIR__)
```

An alternative approach could be to symlink the `phoenix-colocated` folder into your `node_modules`
folder.

> #### Tip {: .info}
>
> If you remove or modify the contents of the `:target_directory` folder, you can use
> `mix clean --all` and `mix compile` to regenerate all colocated JavaScript.

> #### Warning! {: .warning}
>
> LiveView assumes full ownership over the configured `:target_directory`. When
> compiling, it will **delete** any files and folders inside the `:target_directory`,
> that it does not associate with a colocated JavaScript module or manifest.

### Imports in colocated JS - Phoenix.LiveView.ColocatedJS (module)

The colocated JS files are fully handled by your bundler. For Phoenix apps, this is typically
`esbuild`. Because colocated JS is extracted to a folder outside the regular `assets` folder,
special care is necessary when you need to import other files inside the colocated JS:

```javascript
import { someFunction } from "some-dependency";
import somethingElse from "@/vendor/vendored-file";
```

While dependencies from `node_modules` should work out of the box, you cannot simply refer to your
`assets/vendor` folder using a relative path. Instead, your bundler needs to be configured to handle
an alias like `@` to resolve to your local `assets` folder. This is configured by default in the
esbuild configuration for new Phoenix 1.8 applications using `esbuild`'s [alias option](https://esbuild.github.io/api/#alias),
as can be seen in the config snippet above (`--alias=@=.`).

### Options - Phoenix.LiveView.ColocatedJS (module)

Colocated JavaScript can be configured through the attributes of the ` ` tag.
The supported attributes are:

  * `name` - The name under which the default export of the script is available when importing
    the manifest. If omitted, the file will be imported for side effects only.

  * `key` - A custom key to use for the export. This is used by `Phoenix.LiveView.ColocatedHook` to
    export all hooks under the named `hooks` export (`export { ... as hooks }`).
    For example, you could set this to `web_components` for each colocated script that defines
    a web component and then import all of them as `import { web_components } from "phoenix-colocated/my_app"`.
    Defaults to `:default`, which means the export will be available under the manifest's `default` export.
    This needs to be a valid JavaScript identifier. When given, a `name` is required as well.

  * `extension` - a custom extension to use when writing the extracted file. The default is `js`.

  * `manifest` - a custom manifest file to use instead of the default `index.js`. For example,
    `web_components.ts`. If you change the manifest, you will need to change the
    path of your JavaScript imports accordingly.

### Phoenix.LiveView.Controller (module)

Helpers for rendering LiveViews from a controller.

### Phoenix.LiveView.Controller.live_render/3 (function)

Renders a live view from a Plug request and sends an HTML response
from within a controller.

It also automatically sets the `@live_module` assign with the value
of the LiveView to be rendered.

### Options - Phoenix.LiveView.Controller.live_render/3 (function)

See `Phoenix.Component.live_render/3` for all supported options.

### Examples - Phoenix.LiveView.Controller.live_render/3 (function)

defmodule ThermostatController do
      use MyAppWeb, :controller

      # "use MyAppWeb, :controller" should import Phoenix.LiveView.Controller.
      # If it does not, you can either import it there or uncomment the line below:
      # import Phoenix.LiveView.Controller

      def show(conn, %{"id" => thermostat_id}) do
        live_render(conn, ThermostatLive, session: %{
          "thermostat_id" => thermostat_id,
          "current_user_id" => get_session(conn, :user_id)
        })
      end
    end

### Phoenix.LiveView.Debug (module)

Functions for runtime introspection and debugging of LiveViews.

This module provides utilities for inspecting and debugging LiveView processes
at runtime. It allows you to:

  * List all currently connected LiveViews
  * Check if a process is a LiveView
  * Get the socket of a LiveView process
  * Inspect LiveComponents rendered in a LiveView

### Examples - Phoenix.LiveView.Debug (module)

# List all LiveViews
    iex> Phoenix.LiveView.Debug.list_liveviews()
    [%{pid: #PID<0.123.0>, view: MyAppWeb.PostLive.Index, topic: "lv:12345678", transport_pid: #PID<0.122.0>}]

    # Check if a process is a LiveView
    iex> Phoenix.LiveView.Debug.liveview_process?(pid(0,123,0))
    true

    # Get the socket of a LiveView process
    iex> Phoenix.LiveView.Debug.socket(pid(0,123,0))
    {:ok, %Phoenix.LiveView.Socket{...}}

    # Get information about LiveComponents
    iex> Phoenix.LiveView.Debug.live_components(pid(0,123,0))
    {:ok, [%{id: "component-1", module: MyAppWeb.PostLive.Index.Component1, ...}]}

### Phoenix.LiveView.Debug.list_liveviews/0 (function)

Returns a list of all currently connected LiveView processes (on the current node).

Each entry is a map with the following keys:

  - `pid`: The PID of the LiveView process.
  - `view`: The module of the LiveView.
  - `topic`: The topic of the LiveView's channel.
  - `transport_pid`: The PID of the transport process.

The `transport_pid` can be used to group LiveViews on the same page.

### Examples - Phoenix.LiveView.Debug.list_liveviews/0 (function)

iex> list_liveviews()
    [%{pid: #PID<0.123.0>, view: MyAppWeb.PostLive.Index, topic: "lv:12345678", transport_pid: #PID<0.122.0>}]

### Phoenix.LiveView.Debug.live_components/1 (function)

Returns a list with information about all LiveComponents rendered in the LiveView.

### Examples - Phoenix.LiveView.Debug.live_components/1 (function)

iex> live_components(pid)
    {:ok,
     [
       %{
         id: "component-1",
         module: MyAppWeb.PostLive.Index.Component1,
         cid: 1,
         assigns: %{
           id: "component-1",
           __changed__: %{},
           flash: %{},
           myself: %Phoenix.LiveComponent.CID{cid: 1},
           ...
         }
       }
     ]}

### Phoenix.LiveView.Debug.liveview_process?/1 (function)

Checks if the given pid is a LiveView process.

### Examples - Phoenix.LiveView.Debug.liveview_process?/1 (function)

iex> list_liveviews() |> Enum.at(0) |> Map.fetch!(:pid) |> liveview_process?()
    true

    iex> liveview_process?(pid(0,456,0))
    false

### Phoenix.LiveView.Debug.socket/1 (function)

Returns the socket of the LiveView process.

### Examples - Phoenix.LiveView.Debug.socket/1 (function)

iex> list_liveviews() |> Enum.at(0) |> Map.fetch!(:pid) |> socket()
    {:ok, %Phoenix.LiveView.Socket{...}}

    iex> socket(pid(0,123,0))
    {:error, :not_alive_or_not_a_liveview}

### Phoenix.LiveView.JS (module)

Provides commands for executing JavaScript utility operations on the client.

JS commands support a variety of utility operations for common client-side
needs, such as adding or removing CSS classes, setting or removing tag attributes,
showing or hiding content, and transitioning in and out with animations.
While these operations can be accomplished via client-side hooks,
JS commands are DOM-patch aware, so operations applied
by the JS APIs will stick to elements across patches from the server.

In addition to purely client-side utilities, the JS commands include a
rich `push` API, for extending the default `phx-` binding pushes with
options to customize targets, loading states, and additional payload values.

If you need to trigger these commands via JavaScript, see [JavaScript interoperability](js-interop.md#js-commands).

### Client Utility Commands - Phoenix.LiveView.JS (module)

The following utilities are included:

  * `add_class` - Add classes to elements, with optional transitions
  * `remove_class` - Remove classes from elements, with optional transitions
  * `toggle_class` - Sets or removes classes from elements, with optional transitions
  * `set_attribute` - Set an attribute on elements
  * `remove_attribute` - Remove an attribute from elements
  * `toggle_attribute` - Sets or removes element attribute based on attribute presence.
  * `ignore_attributes` - Marks attributes as ignored, skipping them when patching the DOM.
  * `show` - Show elements, with optional transitions
  * `hide` - Hide elements, with optional transitions
  * `toggle` - Shows or hides elements based on visibility, with optional transitions
  * `transition` - Apply a temporary transition to elements for animations
  * `dispatch` - Dispatch a DOM event to elements

For example, the following modal component can be shown or hidden on the
client without a trip to the server:

    alias Phoenix.LiveView.JS

    def hide_modal(js \\ %JS{}) do
      js
      |> JS.hide(transition: "fade-out", to: "#modal")
      |> JS.hide(transition: "fade-out-scale", to: "#modal-content")
    end

    def modal(assigns) do
      ~H"""
       
         
           ✖ 
           {@text} 
         
       
      """
    end

### Enhanced push events - Phoenix.LiveView.JS (module)

The `push/1` command allows you to extend the built-in pushed event handling
when a `phx-` event is pushed to the server. For example, you may wish to
target a specific component, specify additional payload values to include
with the event, apply loading states to external elements, etc. For example,
given this basic `phx-click` event:

```heex
 + 
```

Imagine you need to target your current component, and apply a loading state
to the parent container while the client awaits the server acknowledgement:

    alias Phoenix.LiveView.JS

    ~H"""
     + 
    """

Push commands also compose with all other utilities. For example,
to add a class when pushing:

```heex
  JS.add_class("warmer", to: ".thermo")
}>+ 
```

Any `phx-value-*` attributes will also be included in the payload, their
values will be overwritten by values given directly to `push/1`. Any
`phx-target` attribute will also be used, and overwritten.

```heex
 + 
```

### DOM Selectors - Phoenix.LiveView.JS (module)

The client utility commands in this module all take an optional DOM selector
using the `:to` option.

This can be a string for a regular DOM selector such as:

```elixir
JS.add_class("warmer", to: ".thermo")
JS.hide(to: "#modal")
JS.show(to: "body a:nth-child(2)")
```

It is also possible to provide scopes to the DOM selector. The following scopes
are available:

 * `{:inner, "selector"}` To target an element within the interacted element.
 * `{:closest, "selector"}` To target the closest element from the interacted
 element upwards.

 For example, if building a dropdown component, the button could use the `:inner`
 scope:

 ```heex
  
    Open me 
    
     I'm in the dropdown menu
    
  
 ```

### Custom JS events with JS.dispatch/1 and window.addEventListener - Phoenix.LiveView.JS (module)

`dispatch/1` can be used to dispatch custom JavaScript events to
elements. For example, you can use `JS.dispatch("click", to: "#foo")`,
to dispatch a click event to an element.

This also means you can augment your elements with custom events,
by using JavaScript's `window.addEventListener` and invoking them
with `dispatch/1`. For example, imagine you want to provide
a copy-to-clipboard functionality in your application. You can
add a custom event for it:

```javascript
window.addEventListener("my_app:clipcopy", (event) => {
  if ("clipboard" in navigator) {
    const text = event.target.textContent;
    navigator.clipboard.writeText(text);
  } else {
    alert("Sorry, your browser does not support clipboard copy.");
  }
});
```

Now you can have a button like this:

```heex
 
  Copy content
 
```

The combination of `dispatch/1` with `window.addEventListener` is
a powerful mechanism to increase the amount of actions you can trigger
client-side from your LiveView code.

You can also use `window.addEventListener` to listen to events pushed
from the server. You can learn more in our [JS interoperability guide](js-interop.md).

### Composing JS commands - Phoenix.LiveView.JS (module)

All the functions in this module optionally accept an existing `%JS{}` struct as the first argument,
allowing you to chain multiple commands, like pushing an event to the server and optimistically hiding
a modal:

```heex
 
  My Modal
 

  JS.remove_class("show", to: "#modal", transition: "fade-out")}>
  hide modal
 
```

Note that the commands themselves are executed on the client in the order they are composed
and the client does not wait for a confirmation before executing the next command. If you chain
`JS.push(...) |> JS.hide(...)`, since hide is a fully client-side command, it hides immediately
after pushing the event, not waiting for the server to respond.

JS commands interacting with the server are documented as such. If you chain multiple commands that
interact with the server, those are also guaranteed to be executed in the order they are composed,
since a LiveView can only handle one event at a time. Therefore, if you do something like

```elixir
JS.push("my-event") |> JS.patch("/my-path?foo=bar")
```

it is guaranteed that the event will be pushed first and the patch will only be handled after
the first event was handled by the LiveView.

### Phoenix.LiveView.JS.add_class/1 (function)

Adds classes to elements.

  * `names` - A string with one or more class names to add.

### Options - Phoenix.LiveView.JS.add_class/1 (function)

* `:to` - An optional DOM selector to add classes to.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.
  * `:transition` - A string of classes to apply before adding classes or
    a 3-tuple containing the transition class, the class to apply
    to start the transition, and the ending transition class, such as:
    `{"ease-out duration-300", "opacity-0", "opacity-100"}`
  * `:time` - The time in milliseconds to apply the transition from `:transition`.
    Defaults to 200.
  * `:blocking` - A boolean flag to block the UI during the transition. Defaults `true`.

### Examples - Phoenix.LiveView.JS.add_class/1 (function)

```heex
 My Item 
 
  highlight!
 
```

### Phoenix.LiveView.JS.add_class/2 (function)

See `add_class/1`.

### Phoenix.LiveView.JS.add_class/3 (function)

See `add_class/1`.

### Phoenix.LiveView.JS.concat/2 (function)

Combines two JS commands, appending the second to the first.

### Phoenix.LiveView.JS.dispatch/2 (function)

Dispatches an event to the DOM.

  * `event` - The string event name to dispatch.

*Note*: All events dispatched are of a type
[CustomEvent](https://developer.mozilla.org/en-US/docs/Web/API/CustomEvent),
with the exception of `"click"`. For a `"click"`, a
[MouseEvent](https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent)
is dispatched to properly simulate a UI click.

For emitted `CustomEvent`'s, the event detail will contain a `dispatcher`,
which references the DOM node that dispatched the JS event to the target
element.

### Options - Phoenix.LiveView.JS.dispatch/2 (function)

* `:to` - An optional DOM selector to dispatch the event to.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.
  * `:detail` - An optional detail map to dispatch along
    with the client event. The details will be available in the
    `event.detail` attribute for event listeners.
  * `:bubbles` – A boolean flag to bubble the event or not. Defaults to `true`.
  * `:blocking` - A boolean flag to block the UI until the event handler calls `event.detail.done()`.
    The done function is injected by LiveView and *must* be called eventually to unblock the UI.
    This is useful to integrate with third party JavaScript based animation libraries.

### Examples - Phoenix.LiveView.JS.dispatch/2 (function)

```javascript
window.addEventListener("click", e => console.log("clicked!", e.detail))
```

```heex
 Click me! 
```

### Phoenix.LiveView.JS.dispatch/3 (function)

See `dispatch/2`.

### Phoenix.LiveView.JS.exec/1 (function)

Executes JS commands located in an element's attribute.

  * `attr` - The string attribute where the JS command is specified

### Options - Phoenix.LiveView.JS.exec/1 (function)

* `:to` - An optional DOM selector to fetch the attribute from.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.

### Examples - Phoenix.LiveView.JS.exec/1 (function)

```heex
 ... 
 close 
```

### Phoenix.LiveView.JS.exec/2 (function)

See `exec/1`.

### Phoenix.LiveView.JS.exec/3 (function)

See `exec/1`.

### Phoenix.LiveView.JS.focus/1 (function)

Sends focus to a selector.

### Options - Phoenix.LiveView.JS.focus/1 (function)

* `:to` - An optional DOM selector to send focus to.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.

### Examples - Phoenix.LiveView.JS.focus/1 (function)

JS.focus(to: "main")

### Phoenix.LiveView.JS.focus/2 (function)

See `focus/1`.

### Phoenix.LiveView.JS.focus_first/1 (function)

Sends focus to the first focusable child in selector.

### Options - Phoenix.LiveView.JS.focus_first/1 (function)

* `:to` - An optional DOM selector to focus.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.

### Examples - Phoenix.LiveView.JS.focus_first/1 (function)

JS.focus_first(to: "#modal")

### Phoenix.LiveView.JS.focus_first/2 (function)

See `focus_first/1`.

### Phoenix.LiveView.JS.hide/1 (function)

Hides elements.

*Note*: Only targets elements that are visible, meaning they have a height and/or width greater than zero.

### Options - Phoenix.LiveView.JS.hide/1 (function)

* `:to` - An optional DOM selector to hide.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.
  * `:transition` - A string of classes to apply before hiding or
    a 3-tuple containing the transition class, the class to apply
    to start the transition, and the ending transition class, such as:
    `{"ease-out duration-300", "opacity-100", "opacity-0"}`
  * `:time` - The time in milliseconds to apply the transition from `:transition`.
    Defaults to 200.
  * `:blocking` - A boolean flag to block the UI during the transition. Defaults `true`.

During the process, the following events will be dispatched to the hidden elements:

  * When the action is triggered on the client, `phx:hide-start` is dispatched.
  * After the time specified by `:time`, `phx:hide-end` is dispatched.

### Examples - Phoenix.LiveView.JS.hide/1 (function)

```heex
 My Item 

 
  hide!
 

 
  hide fancy!
 
```

### Phoenix.LiveView.JS.hide/2 (function)

See `hide/1`.

### Phoenix.LiveView.JS.ignore_attributes/1 (function)

Mark attributes as ignored, skipping them when patching the DOM.

Accepts a single attribute name or a list of attribute names.
An asterisk `*` can be used as a wildcard.

Once set, the given attributes will not be patched across LiveView updates.
This includes attributes that are removed by the server.

If you need to "unmark" an attribute, you need to call `ignore_attributes/1` again
with an updated list of attributes.

This is mostly useful in combination with the `phx-mounted` binding, for example:

```heex
 
  ...
 
```

### Options - Phoenix.LiveView.JS.ignore_attributes/1 (function)

* `:to` - An optional DOM selector to select the target element.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.

### Examples - Phoenix.LiveView.JS.ignore_attributes/1 (function)

JS.ignore_attributes(["open", "data-*"], to: "#my-dialog")

### Phoenix.LiveView.JS.ignore_attributes/2 (function)



### Phoenix.LiveView.JS.ignore_attributes/3 (function)



### Phoenix.LiveView.JS.navigate/1 (function)

Sends a navigation event to the server and updates the browser's pushState history.

### Options - Phoenix.LiveView.JS.navigate/1 (function)

* `:replace` - Whether to replace the browser's pushState history. Defaults to `false`.

### Examples - Phoenix.LiveView.JS.navigate/1 (function)

JS.navigate("/my-path")

### Phoenix.LiveView.JS.navigate/2 (function)

See `navigate/1`.

### Phoenix.LiveView.JS.navigate/3 (function)

See `navigate/1`.

### Phoenix.LiveView.JS.patch/1 (function)

Sends a patch event to the server and updates the browser's pushState history.

### Options - Phoenix.LiveView.JS.patch/1 (function)

* `:replace` - Whether to replace the browser's pushState history. Defaults to `false`.

### Examples - Phoenix.LiveView.JS.patch/1 (function)

JS.patch("/my-path")

### Phoenix.LiveView.JS.patch/2 (function)

See `patch/1`.

### Phoenix.LiveView.JS.patch/3 (function)

See `patch/1`.

### Phoenix.LiveView.JS.pop_focus/1 (function)

Focuses the last pushed element.

### Examples - Phoenix.LiveView.JS.pop_focus/1 (function)

JS.pop_focus()

### Phoenix.LiveView.JS.push/1 (function)

Pushes an event to the server.

  * `event` - The string event name to push.

### Options - Phoenix.LiveView.JS.push/1 (function)

* `:target` - A selector or component ID to push to. This value will
    overwrite any `phx-target` attribute present on the element.
  * `:loading` - A selector to apply the phx loading classes to,
    such as `phx-click-loading` in case the event was triggered by
    `phx-click`. The element will be locked from server updates
    until the push is acknowledged by the server.
  * `:page_loading` - Boolean to trigger the phx:page-loading-start and
    phx:page-loading-stop events for this push. Defaults to `false`.
  * `:value` - A map of values to send to the server. These values will be
    merged over any `phx-value-*` attributes that are present on the element.
    All keys will be treated as strings when merging. When used on a form event
    like `phx-change` or `phx-submit`, the precedence is
    `JS.push value > phx-value-* > input value`.

### Examples - Phoenix.LiveView.JS.push/1 (function)

```heex
 click me! 
 click me! 
 click me! 
```

### Phoenix.LiveView.JS.push/2 (function)

See `push/1`.

### Phoenix.LiveView.JS.push/3 (function)

See `push/1`.

### Phoenix.LiveView.JS.push_focus/1 (function)

Pushes focus from the source element to be later popped.

### Options - Phoenix.LiveView.JS.push_focus/1 (function)

* `:to` - An optional DOM selector to push focus to.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.

### Examples - Phoenix.LiveView.JS.push_focus/1 (function)

JS.push_focus()
    JS.push_focus(to: "#my-button")

### Phoenix.LiveView.JS.push_focus/2 (function)

See `push_focus/1`.

### Phoenix.LiveView.JS.remove_attribute/1 (function)

Removes an attribute from elements.

  * `attr` - The string attribute name to remove.

### Options - Phoenix.LiveView.JS.remove_attribute/1 (function)

* `:to` - An optional DOM selector to remove attributes from.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.

### Examples - Phoenix.LiveView.JS.remove_attribute/1 (function)

```heex
 
  hide
 
```

### Phoenix.LiveView.JS.remove_attribute/2 (function)

See `remove_attribute/1`.

### Phoenix.LiveView.JS.remove_attribute/3 (function)

See `remove_attribute/1`.

### Phoenix.LiveView.JS.remove_class/1 (function)

Removes classes from elements.

  * `names` - A string with one or more class names to remove.

### Options - Phoenix.LiveView.JS.remove_class/1 (function)

* `:to` - An optional DOM selector to remove classes from.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.
  * `:transition` - A string of classes to apply before removing classes or
    a 3-tuple containing the transition class, the class to apply
    to start the transition, and the ending transition class, such as:
    `{"ease-out duration-300", "opacity-0", "opacity-100"}`
  * `:time` - The time in milliseconds to apply the transition from `:transition`.
    Defaults to 200.
  * `:blocking` - A boolean flag to block the UI during the transition. Defaults `true`.

### Examples - Phoenix.LiveView.JS.remove_class/1 (function)

```heex
 My Item 
 
  remove highlight!
 
```

### Phoenix.LiveView.JS.remove_class/2 (function)

See `remove_class/1`.

### Phoenix.LiveView.JS.remove_class/3 (function)

See `remove_class/1`.

### Phoenix.LiveView.JS.set_attribute/1 (function)

Sets an attribute on elements.

Accepts a tuple containing the string attribute name/value pair.

### Options - Phoenix.LiveView.JS.set_attribute/1 (function)

* `:to` - An optional DOM selector to add attributes to.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.

### Examples - Phoenix.LiveView.JS.set_attribute/1 (function)

```heex
 
  show
 
```

### Phoenix.LiveView.JS.set_attribute/2 (function)

See `set_attribute/1`.

### Phoenix.LiveView.JS.set_attribute/3 (function)

See `set_attribute/1`.

### Phoenix.LiveView.JS.show/1 (function)

Shows elements.

*Note*: Only targets elements that are hidden, meaning they have a height and/or width equal to zero.

### Options - Phoenix.LiveView.JS.show/1 (function)

* `:to` - An optional DOM selector to show.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.
  * `:transition` - A string of classes to apply before showing or
    a 3-tuple containing the transition class, the class to apply
    to start the transition, and the ending transition class, such as:
    `{"ease-out duration-300", "opacity-0", "opacity-100"}`
  * `:time` - The time in milliseconds to apply the transition from `:transition`.
    Defaults to 200.
  * `:blocking` - A boolean flag to block the UI during the transition. Defaults `true`.
  * `:display` - An optional display value to set when showing. Defaults to `"block"`.

During the process, the following events will be dispatched to the shown elements:

  * When the action is triggered on the client, `phx:show-start` is dispatched.
  * After the time specified by `:time`, `phx:show-end` is dispatched.

### Examples - Phoenix.LiveView.JS.show/1 (function)

```heex
 My Item 

 
  show!
 

 
  show fancy!
 
```

### Phoenix.LiveView.JS.show/2 (function)

See `show/1`.

### Phoenix.LiveView.JS.t/0 (type)



### Phoenix.LiveView.JS.toggle/1 (function)

Toggles element visibility.

### Options - Phoenix.LiveView.JS.toggle/1 (function)

* `:to` - An optional DOM selector to toggle.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.
  * `:in` - A string of classes to apply when toggling in, or
    a 3-tuple containing the transition class, the class to apply
    to start the transition, and the ending transition class, such as:
    `{"ease-out duration-300", "opacity-0", "opacity-100"}`
  * `:out` - A string of classes to apply when toggling out, or
    a 3-tuple containing the transition class, the class to apply
    to start the transition, and the ending transition class, such as:
    `{"ease-out duration-300", "opacity-100", "opacity-0"}`
  * `:time` - The time in milliseconds to apply the transition `:in` and `:out` classes.
    Defaults to 200.
  * `:display` - An optional display value to set when toggling in. Defaults
    to `"block"`.
  * `:blocking` - A boolean flag to block the UI during the transition. Defaults `true`.

When the toggle is complete on the client, a `phx:show-start` or `phx:hide-start`, and
`phx:show-end` or `phx:hide-end` event will be dispatched to the toggled elements.

### Examples - Phoenix.LiveView.JS.toggle/1 (function)

```heex
 My Item 

 
  toggle item!
 

 
  toggle fancy!
 
```

### Phoenix.LiveView.JS.toggle/2 (function)

See `toggle/1`.

### Phoenix.LiveView.JS.toggle_attribute/1 (function)

Sets or removes element attribute based on attribute presence.

Accepts a two or three-element tuple:

* `{attr, val}` - Sets the attribute to the given value or removes it
* `{attr, val1, val2}` - Toggles the attribute between `val1` and `val2`

### Options - Phoenix.LiveView.JS.toggle_attribute/1 (function)

* `:to` - An optional DOM selector to set or remove attributes from.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.

### Examples - Phoenix.LiveView.JS.toggle_attribute/1 (function)

```heex
 
  toggle
 

 
  toggle
 
```

### Phoenix.LiveView.JS.toggle_attribute/2 (function)

See `toggle_attribute/1`.

### Phoenix.LiveView.JS.toggle_attribute/3 (function)

See `toggle_attribute/1`.

### Phoenix.LiveView.JS.toggle_class/1 (function)

Adds or removes element classes based on presence.

  * `names` - A string with one or more class names to toggle.

### Options - Phoenix.LiveView.JS.toggle_class/1 (function)

* `:to` - An optional DOM selector to target.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.
  * `:transition` - A string of classes to apply before adding classes or
    a 3-tuple containing the transition class, the class to apply
    to start the transition, and the ending transition class, such as:
    `{"ease-out duration-300", "opacity-0", "opacity-100"}`
  * `:time` - The time in milliseconds to apply the transition from `:transition`.
    Defaults to 200.
  * `:blocking` - A boolean flag to block the UI during the transition. Defaults `true`.

### Examples - Phoenix.LiveView.JS.toggle_class/1 (function)

```heex
 My Item 
 
  toggle active!
 
```

### Phoenix.LiveView.JS.toggle_class/2 (function)



### Phoenix.LiveView.JS.toggle_class/3 (function)



### Phoenix.LiveView.JS.transition/1 (function)

Transitions elements.

  * `transition` - A string of classes to apply during the transition or
    a 3-tuple containing the transition class, the class to apply
    to start the transition, and the ending transition class, such as:
    `{"ease-out duration-300", "opacity-0", "opacity-100"}`

Transitions are useful for temporarily adding an animation class
to elements, such as for highlighting content changes.

### Options - Phoenix.LiveView.JS.transition/1 (function)

* `:to` - An optional DOM selector to apply transitions to.
    Defaults to the interacted element. See the `DOM selectors`
    section for details.
  * `:time` - The time in milliseconds to apply the transition from `:transition`.
    Defaults to 200.
  * `:blocking` - A boolean flag to block the UI during the transition. Defaults `true`.

### Examples - Phoenix.LiveView.JS.transition/1 (function)

```heex
 My Item 
 Shake! 

 
    duration-300 milliseconds matches time: 300 milliseconds
 
```

### Phoenix.LiveView.JS.transition/2 (function)

See `transition/1`.

### Phoenix.LiveView.JS.transition/3 (function)

See `transition/1`.

### Phoenix.LiveView.Router (module)

Provides LiveView routing for Phoenix routers.

### Phoenix.LiveView.Router.fetch_live_flash/2 (function)

Fetches the LiveView and merges with the controller flash.

Replaces the default `:fetch_flash` plug used by `Phoenix.Router`.

### Examples - Phoenix.LiveView.Router.fetch_live_flash/2 (function)

defmodule MyAppWeb.Router do
      use LiveGenWeb, :router
      import Phoenix.LiveView.Router

      pipeline :browser do
        ...
        plug :fetch_live_flash
      end
      ...
    end

### Phoenix.LiveView.Router.live/4 (macro)

Defines a LiveView route.

A LiveView can be routed to by using the `live` macro with a path and
the name of the LiveView:

    live "/thermostat", ThermostatLive

To navigate to this route within your app, you can use `Phoenix.VerifiedRoutes`:

    push_navigate(socket, to: ~p"/thermostat")
    push_patch(socket, to: ~p"/thermostat?page=#{page}")

> #### HTTP requests {: .info}
>
> The HTTP request method that a route defined by the `live/4` macro
> responds to is `GET`.

### Actions and live navigation - Phoenix.LiveView.Router.live/4 (macro)

It is common for a LiveView to have multiple states and multiple URLs.
For example, you can have a single LiveView that lists all articles on
your web app. For each article there is an "Edit" button which, when
pressed, opens up a modal on the same page to edit the article. It is a
best practice to use live navigation in those cases, so when you click
edit, the URL changes to "/articles/1/edit", even though you are still
within the same LiveView. Similarly, you may also want to show a "New"
button, which opens up the modal to create new entries, and you want
this to be reflected in the URL as "/articles/new".

In order to make it easier to recognize the current "action" your
LiveView is on, you can pass the action option when defining LiveViews
too:

    live "/articles", ArticleLive.Index, :index
    live "/articles/new", ArticleLive.Index, :new
    live "/articles/:id/edit", ArticleLive.Index, :edit

The current action will always be available inside the LiveView as
the `@live_action` assign, that can be used to render a LiveComponent:

```heex
<.live_component :if={@live_action == :new} module={MyAppWeb.ArticleLive.FormComponent} id="form" />
```

Or can be used to show or hide parts of the template:

```heex
{if @live_action == :edit, do: render("form.html", user: @user)}
```

Note that `@live_action` will be `nil` if no action is given on the route definition.

### Options - Phoenix.LiveView.Router.live/4 (macro)

* `:container` - an optional tuple for the HTML tag and DOM attributes to
    be used for the LiveView container. For example: `{:li, style: "color: blue;"}`.
    See `Phoenix.Component.live_render/3` for more information and examples.

  * `:as` - optionally configures the named helper. Defaults to `:live` when
    using a LiveView without actions or defaults to the LiveView name when using
    actions.

  * `:metadata` - a map to optional feed metadata used on telemetry events and route info,
    for example: `%{route_name: :foo, access: :user}`. This data can be retrieved by
    calling `Phoenix.Router.route_info/4` with the `uri` from the `handle_params`
    callback. This can be used to customize a LiveView which may be invoked from
    different routes.

  * `:private` - an optional map of private data to put in the *plug connection*,
    for example: `%{route_name: :foo, access: :user}`. The data will be available
    inside `conn.private` in plug functions.

### Examples - Phoenix.LiveView.Router.live/4 (macro)

defmodule MyApp.Router
      use Phoenix.Router
      import Phoenix.LiveView.Router

      scope "/", MyApp do
        pipe_through [:browser]

        live "/thermostat", ThermostatLive
        live "/clock", ClockLive
        live "/dashboard", DashboardLive, container: {:main, class: "row"}
      end
    end

    iex> MyApp.Router.Helpers.live_path(MyApp.Endpoint, MyApp.ThermostatLive)
    "/thermostat"

### Phoenix.LiveView.Router.live_session/3 (macro)

Defines a live session for live redirects within a group of live routes.

`live_session/3` allow routes defined with `live/4` to support
`navigate` redirects from the client with navigation purely over the existing
websocket connection. This allows live routes defined in the router to
mount a new root LiveView without additional HTTP requests to the server.
For backwards compatibility reasons, all live routes defined outside
of any live session are considered part of a single unnamed live session.

### Security Considerations - Phoenix.LiveView.Router.live_session/3 (macro)

In a regular web application, we perform authentication and authorization
checks on every request. Given LiveViews start as a regular HTTP request,
they share the authentication logic with regular requests through plugs.
Once the user is authenticated, we typically validate the sessions on
the `mount` callback. Authorization rules generally happen on `mount`
(for instance, is the user allowed to see this page?) and also on
`handle_event` (is the user allowed to delete this item?). Performing
authorization on mount is important because `navigate`s *do not go
through the plug pipeline*.

`live_session` can be used to draw boundaries between groups of LiveViews.
Redirecting between `live_session`s will always force a full page reload
and establish a brand new LiveView connection. This is useful when LiveViews
require different authentication strategies or simply when they use different
root layouts (as the root layout is not updated between live redirects).

Please [read our guide on the security model](security-model.md) for a
detailed description and general tips on authentication, authorization,
and more.

> #### `live_session` and `forward` {: .warning}
>
> `live_session` does not currently work with `forward`. LiveView expects
> your `live` routes to always be directly defined within the main router
> of your application.

> #### `live_session` and `scope` {: .warning}
>
> Aliases set with `Phoenix.Router.scope/2` are not expanded in `live_session` arguments.
> You must use the full module name instead.

### Options - Phoenix.LiveView.Router.live_session/3 (macro)

* `:session` - An optional extra session map or MFA tuple to be merged with
    the LiveView session. For example, `%{"admin" => true}` or `{MyMod, :session, []}`.
    For MFA, the function is invoked and the `Plug.Conn` struct is prepended
    to the arguments list.

  * `:root_layout` - An optional root layout tuple for the initial HTTP render to
    override any existing root layout set in the router.

  * `:on_mount` - An optional list of hooks to attach to the mount lifecycle _of
    each LiveView in the session_. See `Phoenix.LiveView.on_mount/1`. Passing a
    single value is also accepted.

  * `:layout` - An optional layout the LiveView will be rendered in. Setting
    this option overrides the layout via `use Phoenix.LiveView`. This option
    may be overridden inside a LiveView by returning `{:ok, socket, layout: ...}`
    from the mount callback

### Examples - Phoenix.LiveView.Router.live_session/3 (macro)

scope "/", MyAppWeb do
      pipe_through :browser

      live_session :default do
        live "/feed", FeedLive, :index
        live "/status", StatusLive, :index
        live "/status/:id", StatusLive, :show
      end

      live_session :admin, on_mount: MyAppWeb.AdminLiveAuth do
        live "/admin", AdminDashboardLive, :index
        live "/admin/posts", AdminPostLive, :index
      end
    end

In the example above, we have two live sessions. Live navigation between live views
in the different sessions is not possible and will always require a full page reload.
This is important in the example above because the `:admin` live session has authentication
requirements, defined by `on_mount: MyAppWeb.AdminLiveAuth`, that the other LiveViews
do not have.

If you have both regular HTTP routes (via get, post, etc) and `live` routes, then
you need to perform the same authentication and authorization rules in both.
For example, if you were to add a `get "/admin/health"` route, then you must create
your own plug that performs the same authentication and authorization rules as
`MyAppWeb.AdminLiveAuth`, and then pipe through it:

    scope "/" do
      # Regular routes
      pipe_through [MyAppWeb.AdminPlugAuth]
      get "/admin/health", AdminHealthController, :index

      # Live routes
      live_session :admin, on_mount: MyAppWeb.AdminLiveAuth do
        live "/admin", AdminDashboardLive, :index
        live "/admin/posts", AdminPostLive, :index
      end
    end

### Phoenix.LiveViewTest (module)

Conveniences for testing function components as well as
LiveViews and LiveComponents.

### Testing function components - Phoenix.LiveViewTest (module)

There are two mechanisms for testing function components. Imagine the
following component:

    def greet(assigns) do
      ~H"""
       Hello, {@name}! 
      """
    end

You can test it by using `render_component/3`, passing the function
reference to the component as first argument:

    import Phoenix.LiveViewTest

    test "greets" do
      assert render_component(&MyComponents.greet/1, name: "Mary") ==
               " Hello, Mary! "
    end

However, for complex components, often the simplest way to test them
is by using the `~H` sigil itself:

    import Phoenix.Component
    import Phoenix.LiveViewTest

    test "greets" do
      assigns = %{}
      assert rendered_to_string(~H"""
              
             """) ==
               " Hello, Mary! "
    end

The difference is that we use `rendered_to_string/1` to convert the rendered
template to a string for testing.

### Testing LiveViews and LiveComponents - Phoenix.LiveViewTest (module)

In LiveComponents and LiveView tests, we interact with views
via process communication in substitution of a browser.
Like a browser, our test process receives messages about the
rendered updates from the view which can be asserted against
to test the life-cycle and behavior of LiveViews and their
children.

### Testing LiveViews - Phoenix.LiveViewTest (module)

The life-cycle of a LiveView as outlined in the `Phoenix.LiveView`
docs details how a view starts as a stateless HTML render in a disconnected
socket state. Once the browser receives the HTML, it connects to the
server and a new LiveView process is started, remounted in a connected
socket state, and the view continues statefully. The LiveView test functions
support testing both disconnected and connected mounts separately, for example:

    import Plug.Conn
    import Phoenix.ConnTest
    import Phoenix.LiveViewTest
    @endpoint MyEndpoint

    test "disconnected and connected mount", %{conn: conn} do
      conn = get(conn, "/my-path")
      assert html_response(conn, 200) =~ " My Disconnected View "

      {:ok, view, html} = live(conn)
    end

    test "redirected mount", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/somewhere"}}} = live(conn, "my-path")
    end

Here, we start by using the familiar `Phoenix.ConnTest` function, `get/2` to
test the regular HTTP GET request which invokes mount with a disconnected socket.
Next, `live/1` is called with our sent connection to mount the view in a connected
state, which starts our stateful LiveView process.

In general, it's often more convenient to test the mounting of a view
in a single step, provided you don't need the result of the stateless HTTP
render. This is done with a single call to `live/2`, which performs the
`get` step for us:

    test "connected mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/my-path")
      assert html =~ " My Connected View "
    end

### Testing Events - Phoenix.LiveViewTest (module)

The browser can send a variety of events to a LiveView via `phx-` bindings,
which are sent to the `handle_event/3` callback. To test events sent by the
browser and assert on the rendered side effect of the event, use the
`render_*` functions:

  * `render_click/1` - sends a phx-click event and value, returning
    the rendered result of the `handle_event/3` callback.

  * `render_focus/2` - sends a phx-focus event and value, returning
    the rendered result of the `handle_event/3` callback.

  * `render_blur/1` - sends a phx-blur event and value, returning
    the rendered result of the `handle_event/3` callback.

  * `render_submit/1` - sends a form phx-submit event and value, returning
    the rendered result of the `handle_event/3` callback.

  * `render_change/1` - sends a form phx-change event and value, returning
    the rendered result of the `handle_event/3` callback.

  * `render_keydown/1` - sends a form phx-keydown event and value, returning
    the rendered result of the `handle_event/3` callback.

  * `render_keyup/1` - sends a form phx-keyup event and value, returning
    the rendered result of the `handle_event/3` callback.

  * `render_hook/3` - sends a hook event and value, returning
    the rendered result of the `handle_event/3` callback.

For example:

    {:ok, view, _html} = live(conn, "/thermo")

    assert view
           |> element("button#inc")
           |> render_click() =~ "The temperature is: 31℉"

In the example above, we are looking for a particular element on the page
and triggering its phx-click event. LiveView takes care of making sure the
element has a phx-click and automatically sends its values to the server.

You can also bypass the element lookup and directly trigger the LiveView
event in most functions:

    assert render_click(view, :inc, %{}) =~ "The temperature is: 31℉"

The `element` style is preferred as much as possible, as it helps LiveView
perform validations and ensure the events in the HTML actually matches the
event names on the server.

### Testing regular messages - Phoenix.LiveViewTest (module)

LiveViews are `GenServer`'s under the hood, and can send and receive messages
just like any other server. To test the side effects of sending or receiving
messages, simply message the view and use the `render` function to test the
result:

    send(view.pid, {:set_temp, 50})
    assert render(view) =~ "The temperature is: 50℉"

### Testing LiveComponents - Phoenix.LiveViewTest (module)

LiveComponents can be tested in two ways. One way is to use the same
`render_component/2` function as function components. This will mount
the LiveComponent and render it once, without testing any of its events:

    assert render_component(MyComponent, id: 123, user: %User{}) =~
             "some markup in component"

However, if you want to test how components are mounted by a LiveView
and interact with DOM events, you must use the regular `live/2` macro
to build the LiveView with the component and then scope events by
passing the view and a **DOM selector** in a list:

    {:ok, view, html} = live(conn, "/users")
    html = view |> element("#user-13 a", "Delete") |> render_click()
    refute html =~ "user-13"
    refute view |> element("#user-13") |> has_element?()

In the example above, LiveView will lookup for an element with
ID=user-13 and retrieve its `phx-target`. If `phx-target` points
to a component, that will be the component used, otherwise it will
fallback to the view.

### Phoenix.LiveViewTest.assert_patch/2 (function)

Asserts a live patch will happen within `timeout` milliseconds.
The default `timeout` is [ExUnit](https://hexdocs.pm/ex_unit/ExUnit.html#configure/1)'s
`assert_receive_timeout` (100 ms).

It returns the new path.

To assert on the flash message, you can assert on the result of the
rendered LiveView.

### Examples - Phoenix.LiveViewTest.assert_patch/2 (function)

render_click(view, :event_that_triggers_patch)
    assert_patch view

    render_click(view, :event_that_triggers_patch)
    assert_patch view, 30

    render_click(view, :event_that_triggers_patch)
    path = assert_patch view
    assert path =~ ~r/path/+/

### Phoenix.LiveViewTest.assert_patch/3 (function)

Asserts a live patch will happen to a given path within `timeout`
milliseconds.

The default `timeout` is [ExUnit](https://hexdocs.pm/ex_unit/ExUnit.html#configure/1)'s
`assert_receive_timeout` (100 ms).

It returns the new path.

To assert on the flash message, you can assert on the result of the
rendered LiveView.

### Examples - Phoenix.LiveViewTest.assert_patch/3 (function)

render_click(view, :event_that_triggers_patch)
    assert_patch view, "/path"

    render_click(view, :event_that_triggers_patch)
    assert_patch view, "/path", 30

### Phoenix.LiveViewTest.assert_patched/2 (function)

Asserts a live patch was performed, and returns the new path.

To assert on the flash message, you can assert on the result of
the rendered LiveView.

### Examples - Phoenix.LiveViewTest.assert_patched/2 (function)

render_click(view, :event_that_triggers_redirect)
    assert_patched view, "/path"

### Phoenix.LiveViewTest.assert_push_event/4 (macro)

Asserts an event will be pushed within `timeout`.
The default `timeout` is [ExUnit](https://hexdocs.pm/ex_unit/ExUnit.html#configure/1)'s
`assert_receive_timeout` (100 ms).

### Examples - Phoenix.LiveViewTest.assert_push_event/4 (macro)

assert_push_event view, "scores", %{points: 100, user: "josé"}

### Phoenix.LiveViewTest.assert_redirect/2 (function)

Asserts a redirect will happen within `timeout` milliseconds.
The default `timeout` is [ExUnit](https://hexdocs.pm/ex_unit/ExUnit.html#configure/1)'s
`assert_receive_timeout` (100 ms).

It returns a tuple containing the new path and the flash messages from said
redirect, if any. Note the flash will contain string keys.

### Examples - Phoenix.LiveViewTest.assert_redirect/2 (function)

render_click(view, :event_that_triggers_redirect)
    {path, flash} = assert_redirect view
    assert flash["info"] == "Welcome"
    assert path =~ ~r/path\/\d+/

    render_click(view, :event_that_triggers_redirect)
    assert_redirect view, 30

### Phoenix.LiveViewTest.assert_redirect/3 (function)

Asserts a redirect will happen to a given path within `timeout` milliseconds.

The default `timeout` is [ExUnit](https://hexdocs.pm/ex_unit/ExUnit.html#configure/1)'s
`assert_receive_timeout` (100 ms).

It returns the flash messages from said redirect, if any.
Note the flash will contain string keys.

### Examples - Phoenix.LiveViewTest.assert_redirect/3 (function)

render_click(view, :event_that_triggers_redirect)
    flash = assert_redirect view, "/path"
    assert flash["info"] == "Welcome"

    render_click(view, :event_that_triggers_redirect)
    assert_redirect view, "/path", 30

### Phoenix.LiveViewTest.assert_redirected/2 (function)

Asserts a redirect was performed.

It returns the flash messages from said redirect, if any. Note the
flash will contain string keys.

### Examples - Phoenix.LiveViewTest.assert_redirected/2 (function)

render_click(view, :event_that_triggers_redirect)
    flash = assert_redirected view, "/path"
    assert flash["info"] == "Welcome"

### Phoenix.LiveViewTest.assert_reply/3 (macro)

Asserts a hook reply was returned from a `handle_event` callback.

The default `timeout` is [ExUnit](https://hexdocs.pm/ex_unit/ExUnit.html#configure/1)'s
`assert_receive_timeout` (100 ms).

### Examples - Phoenix.LiveViewTest.assert_reply/3 (macro)

assert_reply view, %{result: "ok", transaction_id: _}

### Phoenix.LiveViewTest.element/3 (function)

Returns an element to scope a function to.

It expects the current LiveView, a query selector, and a text filter.

An optional text filter may be given to filter the results by the query
selector. If the text filter is a string or a regex, it will match any
element that contains the string (including as a substring) or matches the
regex.

So a link containing the text "unopened" will match `element("a", "opened")`.
To prevent this, a regex could specify that "opened" appear without the prefix "un".
For example, `element("a", ~r{(?<!un)opened})`.
But it may be clearer to add an HTML attribute to make the element easier to
select.

After the text filter is applied, only one element must remain, otherwise an
error is raised.

If no text filter is given, then the query selector itself must return
a single element.

    assert view
          |> element("#term > :first-child", "Increment")
          |> render() =~ "Increment "

Attribute selectors are also supported, and may be used on special cases
like ids which contain periods:

    assert view
           |> element(~s{[href="/foo"][id="foo.bar.baz"]})
           |> render() =~ "Increment "

### Phoenix.LiveViewTest.file_input/4 (macro)

Builds a file input for testing uploads within a form.

Given the form DOM selector, the upload name, and a list of maps of client metadata
for the upload, the returned file input can be passed to `render_upload/2`.

Client metadata takes the following form:

  * `:last_modified` - the last modified timestamp
  * `:name` - the name of the file
  * `:content` - the binary content of the file
  * `:size` - the byte size of the content
  * `:type` - the MIME type of the file
  * `:relative_path` - for simulating webkitdirectory metadata
  * `:meta` - optional metadata sent by the client

### Examples - Phoenix.LiveViewTest.file_input/4 (macro)

avatar = file_input(lv, "#my-form-id", :avatar, [%{
      last_modified: 1_594_171_879_000,
      name: "myfile.jpeg",
      content: File.read!("myfile.jpg"),
      size: 1_396_009,
      type: "image/jpeg"
    }])

    assert render_upload(avatar, "myfile.jpeg") =~ "100%"

### Phoenix.LiveViewTest.find_live_child/2 (function)

Gets the nested LiveView child by `child_id` from the `parent` LiveView.

### Examples - Phoenix.LiveViewTest.find_live_child/2 (function)

{:ok, view, _html} = live(conn, "/thermo")
    assert clock_view = find_live_child(view, "clock")
    assert render_click(clock_view, :snooze) =~ "snoozing"

### Phoenix.LiveViewTest.follow_redirect/3 (macro)

Follows the redirect from a `render_*` action or an `{:error, redirect}`
tuple.

Imagine you have a LiveView that redirects on a `render_click`
event. You can make sure it immediately redirects after the
`render_click` action by calling `follow_redirect/3`:

    live_view
    |> render_click("redirect")
    |> follow_redirect(conn)

Or in the case of an error tuple:

    assert {:error, {:redirect, %{to: "/somewhere"}}} = result = live(conn, "my-path")
    {:ok, view, html} = follow_redirect(result, conn)

`follow_redirect/3` expects a connection as second argument.
This is the connection that will be used to perform the underlying
request.

If the LiveView redirects with a live redirect, this macro returns
`{:ok, live_view, disconnected_html}` with the content of the new
LiveView, the same as the `live/3` macro. If the LiveView redirects
with a regular redirect, this macro returns `{:ok, conn}` with the
rendered redirected page. In any other case, this macro raises.

Finally, note that you can optionally assert on the path you are
being redirected to by passing a third argument:

    live_view
    |> render_click("redirect")
    |> follow_redirect(conn, "/redirected/page")

### Phoenix.LiveViewTest.follow_trigger_action/2 (macro)

Receives a `form_element` and asserts that `phx-trigger-action` has been
set to true, following up on that request.

Imagine you have a LiveView that sends an HTTP form submission. Say that it
sets the `phx-trigger-action` to true, as a response to a submit event.
You can follow the trigger action like this:

    form = form(live_view, selector, %{"form" => "data"})

    # First we submit the form. Optionally verify that phx-trigger-action
    # is now part of the form.
    assert render_submit(form) =~ ~r/phx-trigger-action/

    # Now follow the request made by the form
    conn = follow_trigger_action(form, conn)
    assert conn.method == "POST"
    assert conn.params == %{"form" => "data"}

### Phoenix.LiveViewTest.form/3 (function)

Returns a form element to scope a function to.

It expects the current LiveView, a query selector, and the form data.
The query selector must return a single element.

The form data will be validated directly against the form markup and
make sure the data you are changing/submitting actually exists, failing
otherwise.

### Examples - Phoenix.LiveViewTest.form/3 (function)

assert view
          |> form("#term", user: %{name: "hello"})
          |> render_submit() =~ "Name updated"

This function is meant to mimic what the user can actually do, so you cannot
 set hidden input values. However, hidden values can be given when calling
 `render_submit/2` or `render_change/2`, see their docs for examples.

### Phoenix.LiveViewTest.has_element?/1 (function)

Checks if the given element exists on the page.

### Examples - Phoenix.LiveViewTest.has_element?/1 (function)

assert view |> element("#some-element") |> has_element?()

### Phoenix.LiveViewTest.has_element?/3 (function)

Checks if the given `selector` with `text_filter` is on `view`.

See `element/3` for more information.

### Examples - Phoenix.LiveViewTest.has_element?/3 (function)

assert has_element?(view, "#some-element")

### Phoenix.LiveViewTest.live/3 (macro)

Spawns a connected LiveView process.

If a `path` is given, then a regular `get(conn, path)`
is done and the page is upgraded to a LiveView. If
no path is given, it assumes a previously rendered
`%Plug.Conn{}` is given, which will be converted to
a LiveView immediately.

### Options - Phoenix.LiveViewTest.live/3 (macro)

* `:on_error` - Can be either `:raise` or `:warn` to control whether
     detected errors like duplicate IDs or live components fail the test or just log
     a warning. Defaults to `:raise`.

### Examples - Phoenix.LiveViewTest.live/3 (macro)

{:ok, view, html} = live(conn, "/path")
    assert view.module == MyLive
    assert html =~ "the count is 3"

    assert {:error, {:redirect, %{to: "/somewhere"}}} = live(conn, "/path")

### Phoenix.LiveViewTest.live_children/1 (function)

Returns the current list of LiveView children for the `parent` LiveView.

Children are returned in the order they appear in the rendered HTML.

### Examples - Phoenix.LiveViewTest.live_children/1 (function)

{:ok, view, _html} = live(conn, "/thermo")
    assert [clock_view] = live_children(view)
    assert render_click(clock_view, :snooze) =~ "snoozing"

### Phoenix.LiveViewTest.live_isolated/3 (macro)

Spawns a connected LiveView process mounted in isolation as the sole rendered element.

Useful for testing LiveViews that are not directly routable, such as those
built as small components to be re-used in multiple parents. Testing routable
LiveViews is still recommended whenever possible since features such as
live navigation require routable LiveViews.

### Options - Phoenix.LiveViewTest.live_isolated/3 (macro)

* `:session` - the session to be given to the LiveView
  * `:on_error` - Can be either `:raise` or `:warn` to control whether
     detected errors like duplicate IDs or live components fail the test or just log
     a warning. Defaults to `:raise`.

All other options are forwarded to the LiveView for rendering. Refer to
`Phoenix.Component.live_render/3` for a list of supported render
options.

### Examples - Phoenix.LiveViewTest.live_isolated/3 (macro)

{:ok, view, html} =
      live_isolated(conn, MyAppWeb.ClockLive, session: %{"tz" => "EST"})

Use `put_connect_params/2` to put connect params for a call to
`Phoenix.LiveView.get_connect_params/1` in `c:Phoenix.LiveView.mount/3`:

    {:ok, view, html} =
      conn
      |> put_connect_params(%{"param" => "value"})
      |> live_isolated(AppWeb.ClockLive, session: %{"tz" => "EST"})

### Phoenix.LiveViewTest.live_redirect/2 (function)

Performs a live redirect from one LiveView to another.

When redirecting between two LiveViews of the same `live_session`,
mounts the new LiveView and shutsdown the previous one, which
mimics general browser live navigation behaviour.

When attempting to navigate from a LiveView of a different
`live_session`, an error redirect condition is returned indicating
a failed `push_navigate` from the client.

### Examples - Phoenix.LiveViewTest.live_redirect/2 (function)

assert {:ok, page_live, _html} = live(conn, "/page/1")
    assert {:ok, page2_live, _html} = live(conn, "/page/2")

    assert {:error, {:redirect, _}} = live_redirect(page2_live, to: "/admin")

### Phoenix.LiveViewTest.open_browser/2 (function)

Open the default browser to display current HTML of `view_or_element`.

### Examples - Phoenix.LiveViewTest.open_browser/2 (function)

view
    |> element("#term > :first-child", "Increment")
    |> open_browser()

    assert view
           |> form("#term", user: %{name: "hello"})
           |> open_browser()
           |> render_submit() =~ "Name updated"

### Phoenix.LiveViewTest.page_title/1 (function)

Returns the most recent title that was updated via a `page_title` assign.

### Examples - Phoenix.LiveViewTest.page_title/1 (function)

render_click(view, :event_that_triggers_page_title_update)
    assert page_title(view) =~ "my title"

### Phoenix.LiveViewTest.preflight_upload/1 (function)

Performs a preflight upload request.

Useful for testing external uploaders to retrieve the `:external` entry metadata.

### Examples - Phoenix.LiveViewTest.preflight_upload/1 (function)

avatar = file_input(lv, "#my-form-id", :avatar, [%{name: ..., ...}, ...])
    assert {:ok, %{ref: _ref, config: %{chunk_size: _}}} = preflight_upload(avatar)

### Phoenix.LiveViewTest.put_connect_params/2 (function)

Puts connect params to be used on LiveView connections.

See `Phoenix.LiveView.get_connect_params/1`.

### Phoenix.LiveViewTest.put_submitter/2 (function)

Puts the submitter `element_or_selector` on the given `form` element.

A submitter is an element that initiates the form's submit event on the client. When a submitter
is put on an element created with `form/3` and then the form is submitted via `render_submit/2`,
the name/value pair of the submitter will be included in the submit event payload.

The given element or selector must exist within the form and match one of the following:

- A `button` or `input` element with `type="submit"`.

- A `button` element without a `type` attribute.

### Examples - Phoenix.LiveViewTest.put_submitter/2 (function)

form = view |> form("#my-form")

    assert form
           |> put_submitter("button[name=example]")
           |> render_submit() =~ "Submitted example"

### Phoenix.LiveViewTest.refute_push_event/4 (macro)

Refutes an event will be pushed within timeout.

The default `timeout` is [ExUnit](https://hexdocs.pm/ex_unit/ExUnit.html#configure/1)'s
`refute_receive_timeout` (100 ms).

### Examples - Phoenix.LiveViewTest.refute_push_event/4 (macro)

refute_push_event view, "scores", %{points: _, user: "josé"}

### Phoenix.LiveViewTest.refute_redirected/1 (function)

Refutes a redirect to a given path was performed.

It returns :ok if the specified redirect isn't already in the mailbox.

If no path is specified, refutes any redirection on the given view.

### Examples - Phoenix.LiveViewTest.refute_redirected/1 (function)

render_click(view, :event_that_triggers_redirect_to_path)
    :ok = refute_redirected view, "/wrong_path"

### Phoenix.LiveViewTest.refute_redirected/2 (function)



### Phoenix.LiveViewTest.render/1 (function)

Returns the HTML string of the rendered view or element.

If a view is provided, the entire LiveView is rendered.
If a view after calling `with_target/2` or an element
are given, only that particular context is returned.

### Examples - Phoenix.LiveViewTest.render/1 (function)

{:ok, view, _html} = live(conn, "/thermo")
    assert render(view) =~ ~s| Snooze |

    assert view
           |> element("#alarm")
           |> render() == "Snooze"

### Phoenix.LiveViewTest.render_async/2 (function)

Awaits all current `assign_async` and `start_async` for a given LiveView or element.

It renders the LiveView or Element once complete and returns the result.
The default `timeout` is [ExUnit](https://hexdocs.pm/ex_unit/ExUnit.html#configure/1)'s
`assert_receive_timeout` (100 ms).

### Examples - Phoenix.LiveViewTest.render_async/2 (function)

{:ok, lv, html} = live(conn, "/path")
    assert html =~ "loading data..."
    assert render_async(lv) =~ "data loaded!"

### Phoenix.LiveViewTest.render_blur/2 (function)

Sends a blur event given by `element` and returns the rendered result.

The `element` is created with `element/3` and must point to a single
element on the page with a `phx-blur` attribute in it. The event name
given set on `phx-blur` is then sent to the appropriate LiveView
(or component if `phx-target` is set accordingly). All `phx-value-*`
entries in the element are sent as values. Extra values can be given
with the `value` argument.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_blur/2 (function)

{:ok, view, html} = live(conn, "/thermo")

    assert view
           |> element("#inactive")
           |> render_blur() =~ "Tap to wake"

### Phoenix.LiveViewTest.render_blur/3 (function)

Sends a blur event to the view and returns the rendered result.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_blur/3 (function)

{:ok, view, html} = live(conn, "/thermo")
    assert html =~ "The temp is: 30℉"
    assert render_blur(view, :inactive) =~ "Tap to wake"

### Phoenix.LiveViewTest.render_change/2 (function)

Sends a form change event given by `element` and returns the rendered result.

The `element` is created with `element/3` and must point to a single
element on the page with a `phx-change` attribute in it. The event name
given set on `phx-change` is then sent to the appropriate LiveView
(or component if `phx-target` is set accordingly). All `phx-value-*`
entries in the element are sent as values.

If you need to pass any extra values or metadata, such as the "_target"
parameter, you can do so by giving a map under the `value` argument.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_change/2 (function)

{:ok, view, html} = live(conn, "/thermo")

    assert view
           |> element("form")
           |> render_change(%{deg: 123}) =~ "123 exceeds limits"

    # Passing metadata
    {:ok, view, html} = live(conn, "/thermo")

    assert view
           |> element("form")
           |> render_change(%{_target: ["deg"], deg: 123}) =~ "123 exceeds limits"

As with `render_submit/2`, hidden input field values can be provided like so:

    refute view
          |> form("#term", user: %{name: "hello"})
          |> render_change(%{user: %{"hidden_field" => "example"}}) =~ "can't be blank"

### Phoenix.LiveViewTest.render_change/3 (function)

Sends a form change event to the view and returns the rendered result.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_change/3 (function)

{:ok, view, html} = live(conn, "/thermo")
    assert html =~ "The temp is: 30℉"
    assert render_change(view, :validate, %{deg: 123}) =~ "123 exceeds limits"

### Phoenix.LiveViewTest.render_click/2 (function)

Sends a click event given by `element` and returns the rendered result.

The `element` is created with `element/3` and must point to a single
element on the page with a `phx-click` attribute in it. The event name
given set on `phx-click` is then sent to the appropriate LiveView
(or component if `phx-target` is set accordingly). All `phx-value-*`
entries in the element are sent as values. Extra values can be given
with the `value` argument.

If the element does not have a `phx-click` attribute but it is
a link (the ` ` tag), the link will be followed accordingly:

  * if the link is a `patch`, the current view will be patched
  * if the link is a `navigate`, this function will return
    `{:error, {:live_redirect, %{to: url}}}`, which can be followed
    with `follow_redirect/2`
  * if the link is a regular link, this function will return
    `{:error, {:redirect, %{to: url}}}`, which can be followed
    with `follow_redirect/2`

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_click/2 (function)

{:ok, view, html} = live(conn, "/thermo")

    assert view
           |> element("button", "Increment")
           |> render_click() =~ "The temperature is: 30℉"

### Phoenix.LiveViewTest.render_click/3 (function)

Sends a click `event` to the `view` with `value` and returns the rendered result.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_click/3 (function)

{:ok, view, html} = live(conn, "/thermo")
    assert html =~ "The temperature is: 30℉"
    assert render_click(view, :inc) =~ "The temperature is: 31℉"

### Phoenix.LiveViewTest.render_component/3 (macro)

Renders a component.

The first argument may either be a function component, as an
anonymous function:

    assert render_component(&Weather.city/1, name: "Kraków") =~
             "some markup in component"

Or a stateful component as a module. In this case, this function
will mount, update, and render the component. The `:id` option is
a required argument:

    assert render_component(MyComponent, id: 123, user: %User{}) =~
             "some markup in component"

If your component is using the router, you can pass it as argument:

    assert render_component(MyComponent, %{id: 123, user: %User{}}, router: SomeRouter) =~
             "some markup in component"

### Phoenix.LiveViewTest.render_focus/2 (function)

Sends a focus event given by `element` and returns the rendered result.

The `element` is created with `element/3` and must point to a single
element on the page with a `phx-focus` attribute in it. The event name
given set on `phx-focus` is then sent to the appropriate LiveView
(or component if `phx-target` is set accordingly). All `phx-value-*`
entries in the element are sent as values. Extra values can be given
with the `value` argument.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_focus/2 (function)

{:ok, view, html} = live(conn, "/thermo")

    assert view
           |> element("#inactive")
           |> render_focus() =~ "Tap to wake"

### Phoenix.LiveViewTest.render_focus/3 (function)

Sends a focus event to the view and returns the rendered result.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_focus/3 (function)

{:ok, view, html} = live(conn, "/thermo")
    assert html =~ "The temp is: 30℉"
    assert render_focus(view, :inactive) =~ "Tap to wake"

### Phoenix.LiveViewTest.render_hook/3 (function)

Sends a hook event to the view or an element and returns the rendered result.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_hook/3 (function)

{:ok, view, html} = live(conn, "/thermo")
    assert html =~ "The temp is: 30℉"
    assert render_hook(view, :refresh, %{deg: 32}) =~ "The temp is: 32℉"

If you are pushing events from a hook to a component, then you must pass
an `element`, created with `element/3`, as first argument and it must point
to a single element on the page with a `phx-target` attribute in it:

    {:ok, view, _html} = live(conn, "/thermo")
    assert view
           |> element("#thermo-component")
           |> render_hook(:refresh, %{deg: 32}) =~ "The temp is: 32℉"

### Phoenix.LiveViewTest.render_keydown/2 (function)

Sends a keydown event given by `element` and returns the rendered result.

The `element` is created with `element/3` and must point to a single element
on the page with a `phx-keydown` or `phx-window-keydown` attribute in it.
The event name given set on `phx-keydown` is then sent to the appropriate
LiveView (or component if `phx-target` is set accordingly). All `phx-value-*`
entries in the element are sent as values. Extra values can be given with
the `value` argument.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_keydown/2 (function)

{:ok, view, html} = live(conn, "/thermo")
    assert html =~ "The temp is: 30℉"
    assert view |> element("#inc") |> render_keydown() =~ "The temp is: 31℉"

### Phoenix.LiveViewTest.render_keydown/3 (function)

Sends a keydown event to the view and returns the rendered result.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_keydown/3 (function)

{:ok, view, html} = live(conn, "/thermo")
    assert html =~ "The temp is: 30℉"
    assert render_keydown(view, :inc) =~ "The temp is: 31℉"

### Phoenix.LiveViewTest.render_keyup/2 (function)

Sends a keyup event given by `element` and returns the rendered result.

The `element` is created with `element/3` and must point to a single
element on the page with a `phx-keyup` or `phx-window-keyup` attribute
in it. The event name given set on `phx-keyup` is then sent to the
appropriate LiveView (or component if `phx-target` is set accordingly).
All `phx-value-*` entries in the element are sent as values. Extra values
can be given with the `value` argument.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_keyup/2 (function)

{:ok, view, html} = live(conn, "/thermo")
    assert html =~ "The temp is: 30℉"
    assert view |> element("#inc") |> render_keyup() =~ "The temp is: 31℉"

### Phoenix.LiveViewTest.render_keyup/3 (function)

Sends a keyup event to the view and returns the rendered result.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_keyup/3 (function)

{:ok, view, html} = live(conn, "/thermo")
    assert html =~ "The temp is: 30℉"
    assert render_keyup(view, :inc) =~ "The temp is: 31℉"

### Phoenix.LiveViewTest.render_patch/2 (function)

Simulates a `push_patch` to the given `path` and returns the rendered result.

### Phoenix.LiveViewTest.render_submit/2 (function)

Sends a form submit event given by `element` and returns the rendered result.

The `element` is created with `element/3` and must point to a single
element on the page with a `phx-submit` attribute in it. The event name
given set on `phx-submit` is then sent to the appropriate LiveView
(or component if `phx-target` is set accordingly). All `phx-value-*`
entries in the element are sent as values. Extra values, including hidden
input fields, can be given with the `value` argument.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_submit/2 (function)

{:ok, view, html} = live(conn, "/thermo")

    assert view
           |> element("form")
           |> render_submit(%{deg: 123, avatar: upload}) =~ "123 exceeds limits"

To submit a form along with some hidden input values:

    assert view
           |> form("#term", user: %{name: "hello"})
           |> render_submit(%{user: %{"hidden_field" => "example"}}) =~ "Name updated"

To submit a form by a specific submit element via `put_submitter/2`:

    assert view
           |> form("#term", user: %{name: "hello"})
           |> put_submitter("button[name=example_action]")
           |> render_submit() =~ "Action taken"

### Phoenix.LiveViewTest.render_submit/3 (function)

Sends a form submit event to the view and returns the rendered result.

It returns the contents of the whole LiveView or an `{:error, redirect}`
tuple.

### Examples - Phoenix.LiveViewTest.render_submit/3 (function)

{:ok, view, html} = live(conn, "/thermo")
    assert html =~ "The temp is: 30℉"
    assert render_submit(view, :refresh, %{deg: 32}) =~ "The temp is: 32℉"

### Phoenix.LiveViewTest.render_upload/3 (function)

Performs an upload of a file input and renders the result.

See `file_input/4` for details on building a file input.

### Examples - Phoenix.LiveViewTest.render_upload/3 (function)

Given the following LiveView template:

```heex
<%= for entry <- @uploads.avatar.entries do %>
  {entry.name}: {entry.progress}%
<% end %>
```

Your test case can assert the uploaded content:

    avatar = file_input(lv, "#my-form-id", :avatar, [
      %{
        last_modified: 1_594_171_879_000,
        name: "myfile.jpeg",
        content: File.read!("myfile.jpg"),
        size: 1_396_009,
        type: "image/jpeg"
      }
    ])

    assert render_upload(avatar, "myfile.jpeg") =~ "100%"

By default, the entire file is chunked to the server, but an optional
percentage to chunk can be passed to test chunk-by-chunk uploads:

    assert render_upload(avatar, "myfile.jpeg", 49) =~ "49%"
    assert render_upload(avatar, "myfile.jpeg", 51) =~ "100%"

Before making assertions about the how the upload is consumed server-side,
you will need to call `render_submit/1`.

In the case where an upload progress callback issues a navigate, patch, or
redirect, the following will be returned:

  * for a patch, the current view will be patched
  * for a navigate, this function will return
    `{:error, {:live_redirect, %{to: url}}}`, which can be followed
    with `follow_redirect/2`
  * for a regular redirect, this function will return
    `{:error, {:redirect, %{to: url}}}`, which can be followed
    with `follow_redirect/2`

### Phoenix.LiveViewTest.rendered_to_string/1 (function)

Converts a rendered template to a string.

### Examples - Phoenix.LiveViewTest.rendered_to_string/1 (function)

import Phoenix.Component
    import Phoenix.LiveViewTest

    test "greets" do
      assigns = %{}
      assert rendered_to_string(~H"""
              
             """) ==
               " Hello, Mary! "
    end

### Phoenix.LiveViewTest.submit_form/2 (macro)

Receives a form element and submits the HTTP request through the plug pipeline.

Imagine you have a LiveView that validates form data, but submits the form to
a controller via the normal form `action` attribute. This is especially useful
in scenarios where the result of a form submit needs to write to the plug session.

You can follow submit the form with the `%Plug.Conn{}`, like this:

    form = form(live_view, selector, %{"form" => "data"})

    # Now submit the LiveView form to the plug pipeline
    conn = submit_form(form, conn)
    assert conn.method == "POST"
    assert conn.params == %{"form" => "data"}

### Phoenix.LiveViewTest.with_target/2 (function)

Sets the target of the view for events.

This emulates `phx-target` directly in tests, without
having to dispatch the event to a specific element.
This can be useful for invoking events to one or
multiple components at the same time:

    view
    |> with_target("#user-1,#user-2")
    |> render_click("Hide", %{})

### Phoenix.LiveView.HTMLFormatter (module)

Format HEEx templates from `.heex` files or `~H` sigils.

This is a `mix format` [plugin](https://hexdocs.pm/mix/main/Mix.Tasks.Format.html#module-plugins).

### Setup - Phoenix.LiveView.HTMLFormatter (module)

Add it as a plugin to your `.formatter.exs` file and make sure to put
the `heex` extension in the `inputs` option.

```elixir
[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{heex,ex,exs}"],
  # ...
]
```

>

### For umbrella projects - Phoenix.LiveView.HTMLFormatter (module)

>
> In umbrella projects you must also change two files at the umbrella root,
> add `:phoenix_live_view` to your `deps` in the `mix.exs` file
> and add `plugins: [Phoenix.LiveView.HTMLFormatter]` in the `.formatter.exs` file.
> This is because the formatter does not attempt to load the dependencies of
> all children applications.

### Editor support - Phoenix.LiveView.HTMLFormatter (module)

Most editors that support `mix format` integration should automatically format
`.heex` and `~H` templates. Other editors may require custom integration or
even provide additional functionality. Here are some reference posts:

  * [Formatting HEEx templates in VS Code](https://pragmaticstudio.com/tutorials/formatting-heex-templates-in-vscode)

### Options - Phoenix.LiveView.HTMLFormatter (module)

* `:line_length` - The Elixir formatter defaults to a maximum line length
    of 98 characters, which can be overwritten with the `:line_length` option
    in your `.formatter.exs` file.

  * `:heex_line_length` - change the line length only for the HEEx formatter.

    ```elixir
    [
      # ...omitted
      heex_line_length: 300
    ]
    ```

  * `:migrate_eex_to_curly_interpolation` - Automatically migrate single expression
    `<%= ... %>` EEx expression to the curly braces one. Defaults to true.

  * `:attribute_formatters` - Specify formatters for certain attributes.

    ```elixir
    [
      plugins: [Phoenix.LiveView.HTMLFormatter],
      attribute_formatters: %{class: ClassFormatter},
    ]
    ```

  * `:inline_matcher` - a list of regular expressions to determine if a component
    should be treated as inline.
    Defaults to `["link", "button"]`, which treats any component with `link`
    or `button` in its name as inline.
    Can be disabled by setting it to an empty list.

### Formatting - Phoenix.LiveView.HTMLFormatter (module)

This formatter tries to be as consistent as possible with the Elixir formatter
and also take into account "block" and "inline" HTML elements.

In the past, HTML elements were categorized as either "block-level" or
"inline". While now these concepts are specified by CSS, the historical
distinction remains as it typically dictates the default browser rendering
behavior. In particular, adding or removing whitespace between the start and
end tags of a block-level element will not change the rendered output, while
it may for inline elements.

The following links further explain these concepts:

* https://developer.mozilla.org/en-US/docs/Glossary/Block-level_content
* https://developer.mozilla.org/en-US/docs/Glossary/Inline-level_content

Given HTML like this:

```heex
        {@user.name}   
```

It will be formatted as:

```heex
 
    {@user.name}  
 
```

A block element will go to the next line, while inline elements will be kept in the current line
as long as they fit within the configured line length.

It will also keep inline elements in their own lines if you intentionally write them this way:

```heex
 
   
     {@user.name} 
   
 
```

This formatter will place all attributes on their own lines when they do not all fit in the
current line. Therefore this:

```heex
 
   Hi 
 
```

Will be formatted to:

```heex
 
   Hi 
 
```

This formatter **does not** format Elixir expressions with `do...end`.
The content within it will be formatted accordingly though. Therefore, the given
input:

```eex
<%= live_redirect(
       to: "/my/path",
  class: "my class"
) do %>
        My Link
<% end %>
```

Will be formatted to

```eex
<%= live_redirect(
       to: "/my/path",
  class: "my class"
) do %>
  My Link
<% end %>
```

Note that only the text `My Link` has been formatted.

### Intentional new lines - Phoenix.LiveView.HTMLFormatter (module)

The formatter will keep intentional new lines. However, the formatter will
always keep a maximum of one line break in case you have multiple ones:

```heex
 
  text


  text
 
```

Will be formatted to:

```heex
 
  text

  text
 
```

### Inline elements - Phoenix.LiveView.HTMLFormatter (module)

We don't format inline elements when there is a text without whitespace before
or after the element. Otherwise it would compromise what is rendered adding
an extra whitespace.

The formatter will consider these tags as inline elements:

- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- ` `
- Tags/components that match the `:inline_matcher` option.

All other tags are considered block elements.

### Skip formatting - Phoenix.LiveView.HTMLFormatter (module)

In case you don't want part of your HTML to be automatically formatted.
You can use the special `phx-no-format` attribute so that the formatter will
skip the element block. Note that this attribute will not be rendered.

Therefore:

```heex
<.textarea phx-no-format>My content</.textarea>
```

Will be kept as is your code editor, but rendered as:

```heex
 My content 
```

### Phoenix.LiveView.HTMLFormatter.is_tag_open/1 (macro)



### Phoenix.LiveView.Logger (module)

Instrumenter to handle logging of `Phoenix.LiveView` and `Phoenix.LiveComponent` life-cycle events.

### Installation - Phoenix.LiveView.Logger (module)

The logger is installed automatically when Live View starts.
By default, the log level is set to `:debug`.

### Module configuration - Phoenix.LiveView.Logger (module)

The log level can be overridden for an individual Live View module:

    use Phoenix.LiveView, log: :debug

To disable logging for an individual Live View module:

    use Phoenix.LiveView, log: false

### Telemetry - Phoenix.LiveView.Logger (module)

The following `Phoenix.LiveView` and `Phoenix.LiveComponent` events are logged:

  - `[:phoenix, :live_view, :mount, :start]`
  - `[:phoenix, :live_view, :mount, :stop]`
  - `[:phoenix, :live_view, :handle_params, :start]`
  - `[:phoenix, :live_view, :handle_params, :stop]`
  - `[:phoenix, :live_view, :handle_event, :start]`
  - `[:phoenix, :live_view, :handle_event, :stop]`
  - `[:phoenix, :live_component, :handle_event, :start]`
  - `[:phoenix, :live_component, :handle_event, :stop]`

See the [Telemetry](./guides/server/telemetry.md) guide for more information.

### Parameter filtering - Phoenix.LiveView.Logger (module)

If enabled, `Phoenix.LiveView.Logger` will filter parameters based on the configuration of `Phoenix.Logger`.

### Phoenix.LiveView.Socket (module)

The LiveView socket for Phoenix Endpoints.

This is typically mounted directly in your endpoint.

    socket "/live", Phoenix.LiveView.Socket,
      websocket: [connect_info: [session: @session_options]]

To share an underlying transport connection between regular
Phoenix channels and LiveView processes, `use Phoenix.LiveView.Socket`
from your own `MyAppWeb.UserSocket` module.

Next, declare your `channel` definitions and optional `connect/3`, and
`id/1` callbacks to handle your channel specific needs, then mount
your own socket in your endpoint:

    socket "/live", MyAppWeb.UserSocket,
      websocket: [connect_info: [session: @session_options]]

If you require session options to be set at runtime, you can use
an MFA tuple. The function it designates must return a keyword list.

    socket "/live", MyAppWeb.UserSocket,
      websocket: [connect_info: [session: {__MODULE__, :runtime_opts, []}]]

    # ...

    def runtime_opts() do
      Keyword.put(@session_options, :domain, host())
    end

### Phoenix.LiveView.Socket.assigns/0 (type)

The data in a LiveView as stored in the socket.

### Phoenix.LiveView.Socket.t/0 (type)



### Phoenix.LiveViewTest.Element (module)

The struct returned by `Phoenix.LiveViewTest.element/3`.

The following public fields represent the element:

  * `selector` - The query selector
  * `text_filter` - The text to further filter the element

See the `Phoenix.LiveViewTest` documentation for usage.

### Phoenix.LiveViewTest.Upload (module)

The struct returned by `Phoenix.LiveViewTest.file_input/4`.

The following public fields represent the element:

  * `selector` - The query selector
  * `entries` - The list of selected file entries

See the `Phoenix.LiveViewTest` documentation for usage.

### Phoenix.LiveViewTest.View (module)

The struct for testing LiveViews.

The following public fields represent the LiveView:

  * `id` - The DOM id of the LiveView
  * `module` - The module of the running LiveView
  * `pid` - The Pid of the running LiveView
  * `endpoint` - The endpoint for the LiveView
  * `target` - The target to scope events to

See the `Phoenix.LiveViewTest` documentation for usage.

### Phoenix.LiveView.UploadConfig (module)

The struct representing an upload.

### Phoenix.LiveView.UploadConfig.t/0 (type)



### Phoenix.LiveView.UploadEntry (module)

The struct representing an upload entry.

### Phoenix.LiveView.UploadEntry.t/0 (type)



### Phoenix.LiveView.UploadWriter (behaviour)

Provide a behavior for writing uploaded chunks to a final destination.

By default, uploads are written to a temporary file on the server and
consumed by the LiveView by reading the temporary file or copying it to
durable location. Some usecases require custom handling of the uploaded
chunks, such as streaming a user's upload to another server. In these cases,
we don't want the chunks to be written to disk since we only need to forward
them on.

**Note**: Upload writers run inside the channel uploader process, so
any blocking work will block the channel  errors will crash the channel process.

Custom implementations of `Phoenix.LiveView.UploadWriter` can be passed to
`allow_upload/3`. To initialize the writer with options, define a 3-arity function
that returns a tuple of `{writer, writer_opts}`. For example imagine
an upload writer that logs the chunk sizes and tracks the total bytes sent by the
client:

    socket
    |> allow_upload(:avatar,
      accept: :any,
      writer: fn _name, _entry, _socket -> {EchoWriter, level: :debug} end
    )

And such an `EchoWriter` could look like this:

    defmodule EchoWriter do
      @behaviour Phoenix.LiveView.UploadWriter

      require Logger

      @impl true
      def init(opts) do
        {:ok, %{total: 0, level: Keyword.fetch!(opts, :level)}}
      end

      @impl true
      def meta(state), do: %{level: state.level}

      @impl true
      def write_chunk(data, state) do
        size = byte_size(data)
        Logger.log(state.level, "received chunk of #{size} bytes")
        {:ok, %{state | total: state.total + size}}
      end

      @impl true
      def close(state, reason) do
        Logger.log(state.level, "closing upload after #{state.total} bytes, #{inspect(reason)}")
        {:ok, state}
      end
    end

When the LiveView consumes the uploaded entry, it will receive the `%{level: ...}`
returned from the meta callback. This allows the writer to keep state as it handles
chunks to be later relayed to the LiveView when consumed.

### Close reasons - Phoenix.LiveView.UploadWriter (behaviour)

The `close/2` callback is called when the upload is complete or cancelled. The following
values can be passed:

  * `:done` - The client sent all expected chunks and the upload is awaiting consumption
  * `:cancel` - The upload was canceled, either by the server or the client navigating away.
  * `{:error, reason}` - The upload was canceled due to an error returned from `write_chunk/2`.
    For example, if `write_chunk/2` returns `{:error, :enoent, state}`, the upload will be cancelled
    and `close/2` will be called with the reason `{:error, :enoent}`.

### Phoenix.LiveView.UploadWriter.close/2 (callback)



### Phoenix.LiveView.UploadWriter.init/1 (callback)



### Phoenix.LiveView.UploadWriter.meta/1 (callback)



### Phoenix.LiveView.UploadWriter.write_chunk/2 (callback)



### Phoenix.LiveComponent.CID (module)

The struct representing an internal unique reference to the component instance,
available as the `@myself` assign in live components.

Read more about the uses of `@myself` in the `Phoenix.LiveComponent` docs.

### Phoenix.LiveView.Component (module)

The struct returned by components in .heex templates.

This component is never meant to be output directly
into the template. It should always be handled by
the diffing algorithm.

### Phoenix.LiveView.Component.t/0 (type)



### Phoenix.LiveView.Comprehension (module)

The struct returned by for-comprehensions in .heex templates.

### Phoenix.LiveView.Comprehension.key/0 (type)



### Phoenix.LiveView.Comprehension.keyed_render_fun/0 (type)



### Phoenix.LiveView.Comprehension.t/0 (type)



### Phoenix.LiveView.Engine (module)

An `EEx` template engine that tracks changes.

This is often used by `Phoenix.LiveView.TagEngine` which also adds
HTML validation. In the documentation below, we will explain how it
works internally. For user-facing documentation, see `Phoenix.LiveView`.

### Phoenix.LiveView.Rendered - Phoenix.LiveView.Engine (module)

Whenever you render a live template, it returns a
`Phoenix.LiveView.Rendered` structure. This structure has
three fields: `:static`, `:dynamic` and `:fingerprint`.

The `:static` field is a list of literal strings. This
allows the Elixir compiler to optimize this list and avoid
allocating its strings on every render.

The `:dynamic` field contains a function that takes a boolean argument
(see "Tracking changes" below), and returns a list of dynamic content.
Each element in the list is either one of:

  1. iodata - which is the dynamic content
  2. nil - the dynamic content did not change
  3. another `Phoenix.LiveView.Rendered` struct, see "Nesting and fingerprinting" below
  4. a `Phoenix.LiveView.Comprehension` struct, see "Comprehensions" below
  5. a `Phoenix.LiveView.Component` struct, see "Component" below

When you render a live template, you can convert the
rendered structure to iodata by alternating the static
and dynamic fields, always starting with a static entry
followed by a dynamic entry. The last entry will always
be static too. So the following structure:

    %Phoenix.LiveView.Rendered{
      static: ["foo", "bar", "baz"],
      dynamic: fn track_changes? -> ["left", "right"] end
    }

Results in the following content to be sent over the wire
as iodata:

    ["foo", "left", "bar", "right", "baz"]

This is also what calling `Phoenix.HTML.Safe.to_iodata/1`
with a `Phoenix.LiveView.Rendered` structure returns.

Of course, the benefit of live templates is exactly
that you do not need to send both static and dynamic
segments every time. So let's talk about tracking changes.

### Tracking changes - Phoenix.LiveView.Engine (module)

By default, a live template does not track changes.
Change tracking can be enabled by including a changed
map in the assigns with the key `__changed__` and passing
`true` to the dynamic parts. The map should contain
the name of any changed field as key and the boolean
true as value. If a field is not listed in `__changed__`,
then it is always considered unchanged.

If a field is unchanged and live believes a dynamic
expression no longer needs to be computed, its value
in the `dynamic` list will be `nil`. This information
can be leveraged to avoid sending data to the client.

### Nesting and fingerprinting - Phoenix.LiveView.Engine (module)

`Phoenix.LiveView` also tracks changes across live
templates. Therefore, if your view has this:

```heex
{render("form.html", assigns)}
```

Phoenix will be able to track what is static and dynamic
across templates, as well as what changed. A rendered
nested `live` template will appear in the `dynamic`
list as another `Phoenix.LiveView.Rendered` structure,
which must be handled recursively.

However, because the rendering of live templates can
be dynamic in itself, it is important to distinguish
which live template was rendered. For example,
imagine this code:

```heex
<%= if something?, do: render("one.html", assigns), else: render("other.html", assigns) %>
```

To solve this, all `Phoenix.LiveView.Rendered` structs
also contain a fingerprint field that uniquely identifies
it. If the fingerprints are equal, you have the same
template, and therefore it is possible to only transmit
its changes.

### Comprehensions - Phoenix.LiveView.Engine (module)

Another optimization done by live templates is to
track comprehensions. If your code has this:

```heex
<%= for point <- @points do %>
  x: {point.x}
  y: {point.y}
<% end %>
```

Instead of rendering all points with both static and
dynamic parts, it returns a `Phoenix.LiveView.Comprehension`
struct with the static parts, that are shared across all
points, and a list of entries with a render function for the
dynamics inside. If `@points` is a list with `%{x: 1, y: 2}`
and `%{x: 3, y: 4}`, the above expression would return:

    %Phoenix.LiveView.Comprehension{
      static: ["\n  x: ", "\n  y: ", "\n"],
      entries: [
        {nil, %{point: %{x: 1, y: 2}}, fn vars_changed, track_changes? -> ... end,
        {nil, %{point: %{x: 3, y: 4}}, fn vars_changed, track_changes? -> ... end,
      ]
    }

This allows live templates to send the static parts only once,
regardless of the number of items. Moreover, the diff algorithm
also tracks the variables introduced by the comprehension as part
of the entries and calculates which variables changed between renders.

In HEEx templates, a `:key` attribute can be provided when using `:for`
on a tag to make the diffing more efficient. By default, the index
of each item is used for diffing, which means that if an element is
prepended to the list, the whole collection is sent again.

### Components - Phoenix.LiveView.Engine (module)

Live also supports stateful components defined with
`Phoenix.LiveComponent`. Since they are stateful, they are always
handled lazily by the diff algorithm.

### Phoenix.LiveView.HTMLEngine (module)

The HTMLEngine that powers `.heex` templates and the `~H` sigil.

It works by adding a HTML parsing and validation layer on top
of `Phoenix.LiveView.TagEngine`.

### Phoenix.LiveView.Rendered (module)

The struct returned by .heex templates.

See a description about its fields and use cases
in `Phoenix.LiveView.Engine` docs.

### Phoenix.LiveView.Rendered.dyn/0 (type)



### Phoenix.LiveView.Rendered.t/0 (type)



### Phoenix.LiveView.TagEngine (behaviour)

An EEx engine that understands tags.

This cannot be directly used by Phoenix applications.
Instead, it is the building block by engines such as
`Phoenix.LiveView.HTMLEngine`.

It is typically invoked like this:

    EEx.compile_string(source,
      engine: Phoenix.LiveView.TagEngine,
      line: 1,
      file: path,
      caller: __CALLER__,
      source: source,
      tag_handler: FooBarEngine
    )

Where `:tag_handler` implements the behaviour defined by this module.

### Phoenix.LiveView.TagEngine.annotate_body/1 (callback)

Callback invoked to add annotations around the whole body of a template.

### Phoenix.LiveView.TagEngine.annotate_caller/2 (callback)

Callback invoked to add caller annotations before a function component is invoked.

### Phoenix.LiveView.TagEngine.annotate_slot/4 (callback)

Callback invoked to add annotations around each slot of a template.

In case the slot is an implicit inner block, the tag meta points to
the component.

### Phoenix.LiveView.TagEngine.classify_type/1 (callback)

Classify the tag type from the given binary.

This must return a tuple containing the type of the tag and the name of tag.
For instance, for LiveView which uses HTML as default tag handler this would
return `{:tag, 'div'}` in case the given binary is identified as HTML tag.

You can also return `{:error, "reason"}` so that the compiler will display this
error.

### Phoenix.LiveView.TagEngine.component/3 (function)

Renders a component defined by the given function.

This function is rarely invoked directly by users. Instead, it is used by `~H`
and other engine implementations to render `Phoenix.Component`s. For example,
the following:

```heex
 
```

Is the same as:

```heex
<%= component(
      &MyApp.Weather.city/1,
      [name: "Kraków"],
      {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
    ) %>
```

### Phoenix.LiveView.TagEngine.handle_attributes/2 (callback)

Implements processing of attributes.

It returns a quoted expression or attributes. If attributes are returned,
the second element is a list where each element in the list represents
one attribute. If the list element is a two-element tuple, it is assumed
the key is the name to be statically written in the template. The second
element is the value which is also statically written to the template whenever
possible (such as binaries or binaries inside a list).

### Phoenix.LiveView.TagEngine.inner_block/2 (macro)

Define a inner block, generally used by slots.

This macro is mostly used by custom HTML engines that provide
a `slot` implementation and rarely called directly. The
`name` must be the assign name the slot/block will be stored
under.

If you're using HEEx templates, you should use its higher
level `<:slot>` notation instead. See `Phoenix.Component`
for more information.

### Phoenix.LiveView.TagEngine.void?/1 (callback)

Returns if the given tag name is void or not.

That's mainly useful for HTML tags and used internally by the compiler. You
can just implement as `def void?(_), do: false` if you want to ignore this.

## Links

- [Online documentation](https://hexdocs.pm/phoenix_live_view)