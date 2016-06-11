-- CBlargh Server

-- Libraries
local template = require("template")
local markdown = markdown and markdown.github or require("3rdparty/markdown")

-- Load Settings
settings = assert(loadfile("settings.lua"))()

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

local function list(path)
	if fs.list and not settings.dontusephysfs then
		return fs.list(path)
	else
		return io.list(path)
	end
end

local function exists(path)
	if fs.exists and not settings.dontusephysfs then
		return fs.exists(path)
	else
		return os.exists(path)
	end
end

local function modtime(path)
	if fs.modtime and not settings.dontusephyfs then
		return fs.modtime(path)
	else
		return io.modtime(path)
	end
end

-- Read template(s) into memory
local main_template = assert(readfile("templates/"..settings.template_pack.."/main.html"))
local about_template = readfile("templates/"..settings.template_pack.."/about.html")
local blog_template = assert(readfile("templates/"..settings.template_pack.."/post.html"))
local fail_template = readfile("templates/"..settings.template_pack.."/notfound.html")

local rss_template = readfile("templates/rss.xml")

-- Put the stuff in the kv store for eventual live reload or something.
kvstore.set("title", settings.title)
kvstore.set("aboutme", settings.aboutme)
kvstore.set("url", settings.url)

kvstore.set("template_main", main_template)
kvstore.set("template_about", about_template)
kvstore.set("template_post", blog_template)
kvstore.set("template_notfound", fail_template)

kvstore.set("template_rss", rss_template)

-- Blog posts here!
local posts = {}
local posts_source = {}
local posts_preview = {}
local posts_title = {}
local modtimes = {}
local titles, err = list(settings.posts_path)
if err then
	print(err)
	os.exit(1)
end
for k, v in pairs(titles) do
	local file = settings.posts_path .. v
	print("post/"..v, "->", file)
	local src = readfile(file)

	if string.sub(src, 1, 2) == "# " then
		posts_title[v] = string.match(src, "^#* ([^\n]*)\n")
		src = src:match("^# [^\n]*\n(.*)$")
	else
		posts_title[v] = v
	end

	modtimes[v] = modtime(file)
	posts_source[v] = src
	posts[v] = markdown(src)

	local preview_src = src
	local preview = ""
	local line_count = 0

	for i = 1, string.len(src) do
		local c = string.sub(src, i, i)
		if c == "\n" then
			if string.sub(src, i, i+1) == "\n\n" then
				line_count = line_count + 1
				if line_count >= 5 then
					break
				end
			end
		elseif string.sub(src, i, i+2) == "```" then
			break
		end
		preview = preview .. c
	end

	preview = preview .. "\n"

	posts_preview[v] = markdown(preview) -- TODO: Check for cut-off markdown stuff
end

print() -- empty line

kvstore.set("posts", posts)
kvstore.set("posts_source", posts_source)
kvstore.set("posts_preview", posts_preview)
kvstore.set("posts_title", posts_title)
kvstore.set("modtimes", modtimes)

-- Load static files into memory.
local static_exists = exists("templates/"..settings.template_pack.."/static")
local static, err
if static_exists then
	static, err = list("templates/"..settings.template_pack.."/static")
	if err then
		print(err)
		os.exit(1)
	end
end

-- The routes
srv.GET("/", mw.new(function() -- Front page
	local template = require("template")
	local modtimes = kvstore.get("modtimes")

	local posts = kvstore.get("posts")

	local res, err = template.render(kvstore.get("template_main"), {
		title=kvstore.get("title"),
		aboutme=kvstore.get("aboutme"),
		posts=kvstore.get("posts"),
		posts_source=kvstore.get("posts_source"),
		posts_preview=kvstore.get("posts_preview"),
		posts_title=kvstore.get("posts_title"),
		url=kvstore.get("url"),
		modtimes=modtimes,
		modtimes_r=table.flip(modtimes),
		os=os,
		table=table,
		string=string
	})

	if err then
		print("Template error:", err)
	end
	content(res)
end, nil, nil, true))

if about_template then
	srv.GET("/about", mw.new(function()
		local template = require("template")
		local modtimes = kvstore.get("modtimes")

		local res, err = template.render(kvstore.get("template_about"), {
			title=kvstore.get("title"),
			aboutme=kvstore.get("aboutme"),
			posts=kvstore.get("posts"),
			posts_source=kvstore.get("posts_source"),
			posts_preview=kvstore.get("posts_preview"),
			posts_title=kvstore.get("posts_title"),
			url=kvstore.get("url"),
			modtimes=modtimes,
			modtimes_r=table.flip(modtimes),
			os=os,
			table=table,
			string=string
		})

		if err then
			print("Template error:", err)
		end
		content(res)
	end, nil, nil, true))
end

srv.GET("/post/:postid", mw.new(function()
	local template = require("template")

	local posts = kvstore.get("posts")
	local posts_source = kvstore.get("posts_source")
	local posts_preview = kvstore.get("posts_preview")
	local posts_title = kvstore.get("posts_title")
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
		post_title=posts_title[postid],
		preview=posts_preview[postid],
		posts=posts,
		posts_source=posts_source,
		posts_preview=posts_preview,
		posts_title=posts_title,
		title=kvstore.get("title"),
		aboutme=kvstore.get("aboutme"),
		url=kvstore.get("url"),
		modtimes=modtimes,
		os=os,
		string=string
	})

	if err then
		print("Template error:", err)
	end
	content(res, respcode)
end, nil, nil, true))

-- Generate RSS
srv.GET("/rss.xml", mw.new(function()
	local template = require("template")

	local modtimes=kvstore.get("modtimes")

	local src = kvstore.get("template_rss")

	local res, err = template.render(src, {
		posts=kvstore.get("posts"),
		posts_source=kvstore.get("posts_source"),
		posts_preview=kvstore.get("posts_preview"),
		posts_title=kvstore.get("posts_title"),
		title=kvstore.get("title"),
		aboutme=kvstore.get("aboutme"),
		url=kvstore.get("url"),
		modtimes=modtimes,
		modtimes_r=table.flip(modtimes),
		os=os,
		table=table,
		string=string
	})
	if err then
		print("Template error:", err)
	end
	content(res, 200, "application/rss+xml; charset=UTF-8")
end, nil, nil, true))

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
