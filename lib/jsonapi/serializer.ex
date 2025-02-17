defmodule JSONAPI.Serializer do
  @moduledoc """
  Serialize a map of data into a properly formatted JSON API response object
  """

  alias JSONAPI.{Config, Utils, View}
  alias Plug.Conn

  require Logger

  @type document :: map()

  @doc """
  Takes a view, data and a optional plug connection and returns a fully JSONAPI Serialized document.
  This assumes you are using the JSONAPI.View and have data in maps or structs.

  Please refer to `JSONAPI.View` for more information. If you are in interested in relationships
  and includes you may also want to reference the `JSONAPI.QueryParser`.
  """
  @spec serialize(View.t(), View.data(), Conn.t() | nil, View.meta() | nil, View.options()) ::
          document()
  def serialize(view, data, conn \\ nil, meta \\ nil, options \\ []) do
    {query_includes, query_page} =
      case conn do
        %Conn{assigns: %{jsonapi_query: %Config{include: include, page: page}}} ->
          {include, page}

        _ ->
          {[], nil}
      end

    {to_include, encoded_data} = encode_data(view, data, conn, query_includes, options)

    encoded_data = %{
      data: encoded_data,
      included: flatten_included(to_include)
    }

    encoded_data =
      if is_map(meta) do
        Map.put(encoded_data, :meta, meta)
      else
        encoded_data
      end

    merge_links(encoded_data, data, view, conn, query_page, remove_links?(), options)
  end

  def encode_data(_view, nil, _conn, _query_includes, _options), do: {[], nil}

  def encode_data(view, data, conn, query_includes, options) when is_list(data) do
    Enum.map_reduce(data, [], fn d, acc ->
      {to_include, encoded_data} = encode_data(view, d, conn, query_includes, options)
      {to_include, acc ++ [encoded_data]}
    end)
  end

  def encode_data(view, data, conn, query_includes, options) do
    valid_includes = get_includes(view, query_includes)

    encoded_data = %{
      id: view.id(data),
      type: view.type(),
      attributes: transform_fields(view.attributes(data, conn)),
      relationships: %{}
    }

    doc = merge_links(encoded_data, data, view, conn, nil, remove_links?(), options)

    doc =
      case view.meta(data, conn) do
        nil -> doc
        meta -> Map.put(doc, :meta, meta)
      end

    encode_relationships(conn, doc, {view, data, query_includes, valid_includes}, options)
  end

  @spec encode_relationships(Conn.t(), document(), tuple(), list()) :: tuple()
  def encode_relationships(conn, doc, {view, data, _, _} = view_info, options) do
    view.relationships()
    |> Enum.filter(&assoc_loaded?(Map.get(data, elem(&1, 0))))
    |> Enum.map_reduce(doc, &build_relationships(conn, view_info, &1, &2, options))
  end

  @spec build_relationships(Conn.t(), tuple(), tuple(), tuple(), list()) :: tuple()
  def build_relationships(
        conn,
        {view, data, query_includes, valid_includes},
        {key, include_view},
        acc,
        options
      ) do
    rel_view =
      case include_view do
        {view, :include} -> view
        view -> view
      end

    rel_data = Map.get(data, key)

    # Build the relationship url
    rel_key = transform_fields(key)
    rel_url = view.url_for_rel(data, rel_key, conn)

    # Build the relationship
    acc =
      put_in(
        acc,
        [:relationships, rel_key],
        encode_relation({rel_view, rel_data, rel_url, conn})
      )

    valid_include_view = include_view(valid_includes, key)

    if {rel_view, :include} == valid_include_view && data_loaded?(rel_data) do
      rel_query_includes =
        if is_list(query_includes) do
          query_includes
          |> Enum.reduce([], fn
            {^key, value}, acc -> acc ++ [value]
            _, acc -> acc
          end)
          |> List.flatten()
        else
          []
        end

      {rel_included, encoded_rel} =
        encode_data(rel_view, rel_data, conn, rel_query_includes, options)

      {rel_included ++ [encoded_rel], acc}
    else
      {nil, acc}
    end
  end

  defp include_view(valid_includes, key) when is_list(valid_includes) do
    valid_includes
    |> Keyword.get(key)
    |> generate_view_tuple
  end

  defp include_view(view, _key), do: generate_view_tuple(view)

  defp generate_view_tuple({view, :include}), do: {view, :include}
  defp generate_view_tuple(view) when is_atom(view), do: {view, :include}

  @spec data_loaded?(map() | list()) :: boolean()
  def data_loaded?(rel_data) do
    assoc_loaded?(rel_data) && (is_map(rel_data) || is_list(rel_data))
  end

  @spec encode_relation(tuple()) :: map()
  def encode_relation({rel_view, rel_data, _rel_url, _conn} = info) do
    case encode_rel_data(rel_view, rel_data) do
      nil ->
        nil

      rel_data ->
        merge_related_links(%{data: rel_data}, info, remove_links?())
    end
  end

  defp merge_base_links(%{links: links} = doc, data, view, conn) do
    view_links = Map.merge(view.links(data, conn), links)
    Map.merge(doc, %{links: view_links})
  end

  defp merge_links(doc, data, view, conn, page, false, options) when is_list(data) do
    links =
      Map.merge(view.pagination_links(data, conn, page, options), %{
        self: view.url_for_pagination(data, conn, page)
      })

    doc
    |> Map.merge(%{links: links})
    |> merge_base_links(data, view, conn)
  end

  defp merge_links(doc, data, view, conn, _page, false, _options) do
    doc
    |> Map.merge(%{links: %{self: view.url_for(data, conn)}})
    |> merge_base_links(data, view, conn)
  end

  defp merge_links(doc, _data, _view, _conn, _page, _remove_links, _options), do: doc

  defp merge_related_links(
         encoded_data,
         {rel_view, rel_data, rel_url, conn},
         false = _remove_links
       ) do
    Map.merge(encoded_data, %{links: %{self: rel_url, related: rel_view.url_for(rel_data, conn)}})
  end

  defp merge_related_links(encoded_rel_data, _info, _remove_links), do: encoded_rel_data

  @spec encode_rel_data(module(), map() | list()) :: map() | nil
  def encode_rel_data(_view, nil), do: nil

  def encode_rel_data(view, data) when is_list(data) do
    Enum.map(data, &encode_rel_data(view, &1))
  end

  def encode_rel_data(view, data) do
    %{
      type: view.type(),
      id: view.id(data)
    }
  end

  # Flatten and unique all the included objects
  @spec flatten_included(keyword()) :: keyword()
  def flatten_included(included) do
    included
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp assoc_loaded?(%{__struct__: Ecto.Association.NotLoaded}), do: false
  defp assoc_loaded?(%JSONAPI.Relationships.NotLoaded{}), do: false
  defp assoc_loaded?(_association), do: true

  defp get_includes(view, query_includes) do
    includes = get_default_includes(view) ++ get_query_includes(view, query_includes)
    Enum.uniq(includes)
  end

  defp get_default_includes(view) do
    rels = view.relationships()

    Enum.filter(rels, fn
      {_k, {_v, :include}} -> true
      _ -> false
    end)
  end

  defp get_query_includes(view, query_includes) do
    rels = view.relationships()

    query_includes
    |> Enum.map(fn
      {include, _} -> Keyword.take(rels, [include])
      include -> Keyword.take(rels, [include])
    end)
    |> List.flatten()
  end

  defp remove_links?, do: Application.get_env(:jsonapi, :remove_links, false)

  defp transform_fields(fields) do
    case Utils.String.field_transformation() do
      :camelize -> Utils.String.expand_fields(fields, &Utils.String.camelize/1)
      :dasherize -> Utils.String.expand_fields(fields, &Utils.String.dasherize/1)
      _ -> fields
    end
  end
end
