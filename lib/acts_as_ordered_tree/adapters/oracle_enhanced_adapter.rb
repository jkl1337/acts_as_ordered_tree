require "acts_as_ordered_tree/relation/recursive"

module ActsAsOrderedTree
  module Relation
    class OracleRecursive < Recursive
      attr_accessor :recursive_query_order

      def build_arel
        if recursive_table_value && recursive_query_value
          join_sql = "INNER JOIN (" +
            recursive_query_sql +
            ") #{recursive_table_value} ON #{recursive_table_value}.id = #{table.name}.id"

          except(:recursive_table, :recursive_query).joins(join_sql).build_arel
        else
          super
        end
      end

      private
      def recursive_query_sql
        q = "WITH #{recursive_table_value} (id, parent_id, position) AS (#{recursive_query_value}) "
        if recursive_query_order
          q << "SEARCH DEPTH FIRST BY position SET p_order "
        end
        q << "SELECT * FROM #{recursive_table_value}"
      end
    end
  end

  module Adapters
    module OracleEnhancedAdapter
      # Recursive ancestors fetcher
      def self_and_ancestors
        if persisted? && !send("#{parent_column}_changed?")
          query = <<-QUERY
            SELECT id, #{parent_column}, 1
            FROM #{self.class.quoted_table_name}
            WHERE #{arel[:id].eq(id).to_sql}
            UNION ALL
            SELECT alias1.id, alias1.#{parent_column}, ancestors.position + 1
            FROM #{self.class.quoted_table_name} alias1
              INNER JOIN self_and_ancestors ON alias1.id = self_and_ancestors.#{parent_column}
          QUERY

          recursive_scope.with_recursive("self_and_ancestors", query).
                          order("self_and_ancestors._depth DESC")
        else
          ancestors + [self]
        end
      end

      # Recursive ancestors fetcher
      def ancestors
        query = <<-QUERY
          SELECT id, #{parent_column}, 1
          FROM #{self.class.quoted_table_name}
          WHERE #{arel[:id].eq(parent.try(:id)).to_sql}
          UNION ALL
          SELECT alias1.id, alias1.#{parent_column}, ancestors.position + 1
          FROM #{self.class.quoted_table_name} alias1
            INNER JOIN ancestors ON alias1.id = ancestors.#{parent_column}
        QUERY

        recursive_scope.with_recursive("ancestors", query).
                        order("ancestors.position DESC")
      end

      def root
        root? ? self : ancestors.first
      end

      def self_and_descendants
        # query = <<-QUERY
        #   SELECT #{primary_key} AS id, #{parent_column}, level, #{position_column}
        #   FROM #{self.class.quoted_table_name}
        #   START WITH #{arel[:id].eq(id).to_sql}
        #   CONNECT BY PRIOR #{primary_key} = #{parent_column}
        #   ORDER SIBLINGS BY #{position_column}
        # QUERY

        # connect_by_scope.with_connect_by("descendants", query)

        query = <<-QUERY
          SELECT id, #{parent_column}, #{position_column}
          FROM #{self.class.quoted_table_name}
          WHERE #{arel[:id].eq(id).to_sql}
          UNION ALL
          SELECT alias1.id, alias1.#{parent_column}, alias1.#{position_column}
          FROM descendants INNER JOIN
            #{self.class.quoted_table_name} alias1 ON alias1.#{parent_column} = descendants.id
        QUERY

        relation = recursive_scope.with_recursive("descendants", query)
        relation.recursive_query_order = true
        relation
      end

      def descendants
        self_and_descendants.where(arel[:id].not_eq(id)).
          order("p_order")
      end

      private
      def connect_by_scope
        ActsAsOrderedTree::Relation::ConnectBy.new(ordered_tree_scope)
      end
      def recursive_scope
        ActsAsOrderedTree::Relation::OracleRecursive.new(ordered_tree_scope)
      end
    end
  end
end
