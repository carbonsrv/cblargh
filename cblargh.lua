-- CBlargh Server

-- Libraries
local template = require("template")
local markdown = markdown and markdown.github or require("3rdparty/markdown")

-- Load Settings
settings = assert(loadfile("settings.lua")())

-- IO Helper
local function readfile(path)
	if fs.readfile then
		return fs.readfile(path)
	else
		local f, err = io.open(path)
		if f then
			local content = f:read("*a")
			f:close()
			return content
		else
			return nil, err
		end
	end
end

-- Read template(s) into memory
local main_template = readfile("templates/"..settings.template_pack.."/main.html")
local blog_template = readfile("templates/"..settings.template_pack.."/post.html")
local fail_template = readfile("templates/"..settings.template_pack.."/notfound.html")

local rss_template = readfile("templates/rss.xml")

-- Put the stuff in the kv store for eventual live reload or something.
kvstore.set("title", settings.title)
kvstore.set("aboutme", settings.aboutme)
kvstore.set("url", settings.url)

kvstore.set("template_main", main_template)
kvstore.set("template_post", blog_template)
kvstore.set("template_notfound", fail_template)

kvstore.set("template_rss", rss_template)

-- Blog posts here!
local posts = {}
local posts_source = {}
local modtimes = {}
local titles, err = (fs.list or io.list)(settings.posts_path)
if err then
	print(err)
	os.exit(1)
end
for k, v in pairs(titles) do
	local file = settings.posts_path .. v
	print("post/"..v, "->", file)
	local src = readfile(file)
	modtimes[v] = io.modtime(file)
	posts_source[v] = src
	posts[v] = markdown(src)
end

print() -- empty line

kvstore.set("posts", posts)
kvstore.set("posts_source", posts_source)
kvstore.set("modtimes", modtimes)

-- Load static files into memory.
local static_exists = os.exists("templates/"..settings.template_pack.."/static")
local static, err
if static_exists then
	static, err = io.list("templates/"..settings.template_pack.."/static")
	if err then
		print(err)
		os.exit(1)
	end
end

-- The routes
srv.GET("/", mw.new(function() -- Front page
	local template = require("template")
	local modtimes = kvstore.get("modtimes")

	local res, err = template.render(kvstore.get("template_main"), {
		title=kvstore.get("title"),
		aboutme=kvstore.get("aboutme"),
		posts=kvstore.get("posts"),
		posts_source=kvstore.get("posts_source"),
		url=kvstore.get("url"),
		modtimes=modtimes,
		modtimes_r=table.flip(modtimes),
		os=os,
		table=table
	})

	if err then
		print("Template error:", err)
	end
	content(res)
end))

srv.GET("/post/:postid", mw.new(function()
	local template = require("template")

	local posts = kvstore.get("posts")
	local posts_source = kvstore.get("posts_source")
	local modtimes=kvstore.get("modtimes")
	local postid = params("postid")

	local src
	local respcode = 200
	if posts[postid] then -- Post exists.
		src = kvstore.get("template_post")
	else -- Render fail template
		src = kvstore.get("template_notfound")
		respcode = 404
	end

	local res, err = template.render(src, {
		postid=postid,
		post=posts[postid],
		posts=posts,
		posts_source=posts_source,
		title=kvstore.get("title"),
		aboutme=kvstore.get("aboutme"),
		url=kvstore.get("url"),
		modtimes=modtimes,
		os=os
	})

	if err then
		print("Template error:", err)
	end
	content(res, respcode)
end))

-- Generate RSS
srv.GET("/rss.xml", mw.new(function()
	local template = require("template")

	local modtimes=kvstore.get("modtimes")

	local src = kvstore.get("template_rss")

	local res, err = template.render(src, {
		posts=kvstore.get("posts"),
		posts_source=kvstore.get("posts_source"),
		title=kvstore.get("title"),
		aboutme=kvstore.get("aboutme"),
		url=kvstore.get("url"),
		modtimes=modtimes,
		modtimes_r=table.flip(modtimes),
		os=os,
		table=table
	})
	if err then
		print("Template error:", err)
	end
	content(res, 200, "application/rss+xml; charset=UTF-8")
end))

if static_exists then
	for _, name in pairs(static) do
		local handler = mw.echo(readfile("templates/"..settings.template_pack.."/static/"..name))
		srv.GET("/theme_static/"..name, handler)
	end
end

if os.exists("content") then
	srv.GET("/content/*path", mw.static("/content"))
end

if srv.DefaultRoute then
	local src, err = template.render(kvstore.get("template_notfound"), {
		title=kvstore.get("title"),
		aboutme=aboutme
	})
	if err then
		print(err)
		os.exit(1)
	end
	srv.DefaultRoute(mw.echo(src, 404))
end
