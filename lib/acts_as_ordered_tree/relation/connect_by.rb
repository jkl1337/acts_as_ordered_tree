require "acts_as_ordered_tree/relation/base"

module Arel
  module Nodes
    class ConnectByPrior < Unary
    end
  end

  module Visitors
    class ToSql < Arel::Visitors::Visitor
      private
      def visit_Arel_Nodes_ConnectByPrior o
        "CONNECT BY PRIOR #{visit o.expr}"
      end

      def visit_Arel_Nodes_StartWith o
        "START_WITH #{visit o.expr}"
      end

      def visit_Arel_Nodes_SelectCore o
        [
          "SELECT",
          (visit(o.top) if o.top),
          (visit(o.set_quantifier) if o.set_quantifier),
          ("#{o.projections.map { |x| visit x }.join ', '}" unless o.projections.empty?),
          ("FROM #{visit(o.source)}" if o.source && !o.source.empty?),
          ("WHERE #{o.wheres.map { |x| visit x }.join ' AND ' }" unless o.wheres.empty?),
          ("GROUP BY #{o.groups.map { |x| visit x }.join ', ' }" unless o.groups.empty?),
          (visit(o.having) if o.having),
        ].compact.join ' '
      end

    end
  end

end

module ActsAsOrderedTree
  module Relation
    # Connect_By relation fixes Rails3.0 issue https://github.com/rails/rails/issues/522 for
    # relations with joins to subqueries
    class ConnectBy < Base
      attr_accessor :connect_by_table_value, :connect_by_query_value

      # relation.with_connect_by("table_name", "SELECT * FROM table_name")
      def with_connect_by(connect_by_table_name, query)
        relation = clone
        relation.connect_by_table_value = connect_by_table_name
        relation.connect_by_query_value = query
        relation
      end

      def build_arel
        if connect_by_table_value && connect_by_query_value
          join_sql = "INNER JOIN (" +
                       connect_by_query_sql +
                     ") #{connect_by_table_value} ON #{connect_by_table_value}.id = #{table.name}.id"

          except(:connect_by_table, :connect_by_query).joins(join_sql).build_arel
        else
          super
        end
      end

      def update_all(updates, conditions = nil, options = {})
        if connect_by_table_value && connect_by_query_value
          scope = where("id IN (SELECT id FROM (#{connect_by_query_sql}) AS #{connect_by_table_value})").
              except(:connect_by_table, :connect_by_query, :limit, :order)

          scope.update_all(updates, conditions, options)
        else
          super
        end
      end

      def except(*skips)
        result = super
        ([:connect_by_table, :connect_by_query] - skips).each do |method|
          result.send("#{method}_value=", send(:"#{method}_value"))
        end

        result
      end

      private
      def connect_by_query_sql
        connect_by_query_value
        # "WITH CONNECT_BY #{connect_by_table_value} AS (#{connect_by_query_value}) " +
        #   "SELECT * FROM #{connect_by_table_value}"
      end
    end
  end
end
