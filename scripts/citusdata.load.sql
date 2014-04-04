COPY customer FROM 'DIR/customer.tbl' DELIMITER AS '|' CSV;
COPY lineitem FROM 'DIR/lineitem.tbl' DELIMITER AS '|' CSV;
COPY nation FROM 'DIR/nation.tbl' DELIMITER AS '|' CSV;
COPY orders FROM 'DIR/orders.tbl' DELIMITER AS '|' CSV;
COPY part FROM 'DIR/part.tbl' DELIMITER AS '|' CSV;
COPY partsupp FROM 'DIR/partsupp.tbl' DELIMITER AS '|' CSV;
COPY region FROM 'DIR/region.tbl' DELIMITER AS '|' CSV;
COPY supplier FROM 'DIR/supplier.tbl' DELIMITER AS '|' CSV;
