create table docx_infos(
id serial primary key,
file_name text not null,
is_used boolean default true,
is_public boolean default false,
created_by int, 
created_at timestamp,
deleted_at timestamp
);

create table docx_users(
id serial primary key,
account text not null,
password text not null,
mail text,
nic_name text,
is_used boolean default true,
user_type int default 0,
may_admin boolean default false,
may_approve boolean default false,
may_delete boolean default false,
created_at timestamp
);

create table docx_auths(
id serial primary key,
info_id int not null,
user_id int not null,
may_approve boolean default false,
created_at timestamp,
created_by int,
updated_at timestamp
);
