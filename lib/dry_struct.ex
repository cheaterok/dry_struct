defmodule DryStruct do
  @moduledoc """
  Macros for defining structs without boilerplate.

  Tries to achieve same goal as typed_struct library:
  https://github.com/ejpcmac/typed_struct

  Not production ready or anything, just a project to get familiar with Elixir macros.
  """

  defmodule Field do
    @moduledoc false

    @enforce_keys ~w(name type default default_set? enforce?)a
    defstruct @enforce_keys

    @type t(value) :: %__MODULE__{
      name: atom(),
      type: Macro.t(),
      default: value | nil,
      default_set?: boolean(),
      enforce?: boolean()
    }

    @type t :: t(any())
  end

  defmacro __using__([]) do
    quote do
      import unquote(__MODULE__), only: [drystruct: 1, drystruct: 2]
    end
  end

  defmacro drystruct(options \\ [], [do: ast] = _block) do
    fields = parse_fields(ast, options)

    enforced_keys = get_enforced_keys(fields)
    defstruct_kwl = form_defstruct_list(fields)
    type_kwl = form_types_keyword_list(fields)

    type_ast = quote do: t :: %__MODULE__{unquote_splicing(type_kwl)}
    spec_ast =
      if options[:opaque] do
        quote do: @opaque unquote(type_ast)
      else
        quote do: @type unquote(type_ast)
      end

    struct_ast =
      quote do
        @enforce_keys unquote(enforced_keys)
        defstruct unquote(defstruct_kwl)

        unquote(spec_ast)
      end

    ast =
      if module_name = options[:module] do
        quote do
          defmodule unquote(module_name) do
            unquote(struct_ast)
          end
        end
      else
        struct_ast
      end

    ast
  end

  @spec parse_fields(Macro.t(), Keyword.t()) :: [Field.t()]
  defp parse_fields(ast, global_options) do
    field_asts =
      case ast do
        {:__block__, _context, fields} -> fields
        [] -> []
        field -> [field]
      end

    global_enforce? = Keyword.get(global_options, :enforce, false)

    field_ast_to_field = fn {:field, _context, field_ast} ->
      [name, type, options] =
        case field_ast do
          [name, type] -> [name, type, []]
          [_name, _type, _options] = v -> v
        end

      {default, default_set?} =
        case Keyword.fetch(options, :default) do
          {:ok, value} -> {value, true}
          :error -> {nil, false}
        end

      %Field{
        name: name,
        type: type,
        default: default,
        default_set?: default_set?,
        enforce?: Keyword.get(options, :enforce, global_enforce?)
      }
    end

    Enum.map(field_asts, field_ast_to_field)
  end

  @spec get_enforced_keys([Field.t()]) :: [atom()]
  defp get_enforced_keys(fields) do
    fields
    |> Stream.filter(& not &1.default_set? and &1.enforce?)
    |> Enum.map(& &1.name)
  end

  @spec form_defstruct_list([Field.t(v)]) :: [atom() | {atom(), v}] when v: any()
  defp form_defstruct_list(fields) do
    Enum.map(fields, fn field ->
      if field.default_set? do
        {field.name, field.default}
      else
        field.name
      end
    end)
  end

  @spec form_types_keyword_list([Field.t()]) :: Keyword.t(Macro.t())
  defp form_types_keyword_list(fields) do
    signature_has_nil? = fn type_ast ->
      types =
        case type_ast do
          {:|, _, types} -> types
          type -> [type]
        end
      Enum.member?(types, nil)
    end

    field_to_type_keyword = fn field ->
      needs_nil_in_signature? = (
        not field.enforce?
        and is_nil(field.default)
        and not signature_has_nil?.(field.type)
      )

      type =
        if needs_nil_in_signature? do
          quote do: unquote(field.type) | nil
        else
          field.type
        end

      {field.name, type}
    end

    Enum.map(fields, field_to_type_keyword)
  end
end
