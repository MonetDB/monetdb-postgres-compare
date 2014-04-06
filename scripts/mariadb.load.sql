COPY customer FROM 'DIR/customer.tbl' WITH DELIMITER AS '|';
COPY lineitem FROM 'DIR/lineitem.tbl' WITH DELIMITER AS '|';
COPY nation FROM 'DIR/nation.tbl' WITH DELIMITER AS '|';
COPY orders FROM 'DIR/orders.tbl' WITH DELIMITER AS '|';
COPY part FROM 'DIR/part.tbl' WITH DELIMITER AS '|';
COPY partsupp FROM 'DIR/partsupp.tbl' WITH DELIMITER AS '|';
COPY region FROM 'DIR/region.tbl' WITH DELIMITER AS '|';
COPY supplier FROM 'DIR/supplier.tbl' WITH DELIMITER AS '|';
