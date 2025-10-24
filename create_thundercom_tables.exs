# Script to create Thundercom tables directly
alias Thunderline.Repo

IO.puts("Creating thunderblock_communities table...")
Repo.query!("""
CREATE TABLE thunderblock_communities (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  community_name text,
  community_slug text,
  community_type text DEFAULT 'standard',
  governance_model text DEFAULT 'hierarchical',
  federation_config jsonb,
  community_config jsonb,
  resource_limits jsonb,
  member_count bigint DEFAULT 0,
  channel_count bigint DEFAULT 0,
  pac_home_count bigint DEFAULT 0,
  owner_id uuid,
  moderator_ids uuid[] DEFAULT '{}',
  member_ids uuid[] DEFAULT '{}',
  invitation_config jsonb,
  community_policies jsonb,
  community_metrics jsonb,
  status text,
  tags text[] DEFAULT '{}',
  metadata jsonb DEFAULT '{}',
  inserted_at timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  cluster_node_id uuid,
  community_id uuid,
  execution_zone_id uuid,
  resource_allocation jsonb DEFAULT '{}',
  performance_metrics jsonb DEFAULT '{}',
  created_at timestamp DEFAULT (now() AT TIME ZONE 'utc'),
  vault_mount_id uuid,
  federation_socket_id uuid
)
""")

IO.puts("Creating communities index...")
Repo.query!("""
CREATE UNIQUE INDEX communities_slug_idx ON thunderblock_communities (community_slug)
""")

IO.puts("Creating thunderblock_channels table...")
Repo.query!("""
CREATE TABLE thunderblock_channels (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  channel_name text NOT NULL,
  channel_slug text NOT NULL,
  channel_type text NOT NULL DEFAULT 'text',
  channel_category text,
  status text NOT NULL DEFAULT 'active',
  visibility text NOT NULL DEFAULT 'public',
  topic text,
  channel_config jsonb NOT NULL,
  voice_config jsonb NOT NULL,
  permissions_override jsonb NOT NULL DEFAULT '{}',
  message_count bigint NOT NULL DEFAULT 0,
  active_participants bigint NOT NULL DEFAULT 0,
  last_message_at timestamp,
  created_by uuid NOT NULL,
  pinned_message_ids uuid[] NOT NULL DEFAULT '{}',
  channel_integrations jsonb NOT NULL,
  moderation_config jsonb NOT NULL,
  channel_metrics jsonb NOT NULL,
  position bigint NOT NULL DEFAULT 0,
  tags text[] NOT NULL DEFAULT '{}',
  metadata jsonb NOT NULL DEFAULT '{}',
  inserted_at timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  community_id uuid REFERENCES thunderblock_communities(id) ON DELETE CASCADE ON UPDATE CASCADE
)
""")

IO.puts("Creating channels index...")
Repo.query!("""
CREATE UNIQUE INDEX channels_slug_community_idx ON thunderblock_channels (channel_slug, community_id)
""")

IO.puts("Creating thunderblock_messages table...")
Repo.query!("""
CREATE TABLE thunderblock_messages (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  content text NOT NULL,
  message_type text NOT NULL DEFAULT 'text',
  sender_id uuid NOT NULL,
  sender_type text NOT NULL DEFAULT 'user',
  status text NOT NULL DEFAULT 'active',
  reply_to_id uuid REFERENCES thunderblock_messages(id) ON DELETE SET NULL ON UPDATE CASCADE,
  thread_root_id uuid REFERENCES thunderblock_messages(id) ON DELETE SET NULL ON UPDATE CASCADE,
  attachments jsonb[] NOT NULL DEFAULT '{}',
  reactions jsonb NOT NULL DEFAULT '{}',
  mentions uuid[] NOT NULL DEFAULT '{}',
  channel_mentions uuid[] NOT NULL DEFAULT '{}',
  role_mentions uuid[] NOT NULL DEFAULT '{}',
  message_flags text[] NOT NULL DEFAULT '{}',
  edit_history jsonb[] NOT NULL DEFAULT '{}',
  ai_metadata jsonb NOT NULL,
  pac_metadata jsonb NOT NULL,
  federation_metadata jsonb NOT NULL,
  search_vector text,
  thread_participant_count bigint NOT NULL DEFAULT 0,
  thread_message_count bigint NOT NULL DEFAULT 0,
  last_thread_activity timestamp,
  moderation_data jsonb NOT NULL,
  message_metrics jsonb NOT NULL,
  ephemeral_until timestamp,
  tags text[] NOT NULL DEFAULT '{}',
  metadata jsonb NOT NULL DEFAULT '{}',
  inserted_at timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  channel_id uuid REFERENCES thunderblock_channels(id) ON DELETE CASCADE ON UPDATE CASCADE,
  community_id uuid REFERENCES thunderblock_communities(id) ON DELETE CASCADE ON UPDATE CASCADE
)
""")

IO.puts("Creating messages index...")
Repo.query!("""
CREATE INDEX messages_channel_time_idx ON thunderblock_messages (channel_id, inserted_at)
""")

IO.puts("\n✅ All Thundercom tables created successfully!")
