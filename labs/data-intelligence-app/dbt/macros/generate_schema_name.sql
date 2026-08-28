{# Use the schema configured on the model verbatim, rather than dbt's default of
   concatenating it onto the target schema (which would give DBT_STAGING_DBT_STAGING). #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
