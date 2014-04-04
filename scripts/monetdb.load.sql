COPY INTO region   FROM 'DIR/region.tbl'   USING DELIMITERS '|', '\n' LOCKED;
COPY INTO nation   FROM 'DIR/nation.tbl'   USING DELIMITERS '|', '\n' LOCKED;
COPY INTO supplier FROM 'DIR/supplier.tbl' USING DELIMITERS '|', '\n' LOCKED;
COPY INTO customer FROM 'DIR/customer.tbl' USING DELIMITERS '|', '\n' LOCKED;
COPY INTO part     FROM 'DIR/part.tbl'     USING DELIMITERS '|', '\n' LOCKED;
COPY INTO partsupp FROM 'DIR/partsupp.tbl' USING DELIMITERS '|', '\n' LOCKED;
COPY INTO orders   FROM 'DIR/orders.tbl'   USING DELIMITERS '|', '\n' LOCKED;
COPY INTO lineitem FROM 'DIR/lineitem.tbl' USING DELIMITERS '|', '\n' LOCKED;