# Description:
#   Interact with your Jenkins CI server
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_JENKINS_URLS
#   HUBOT_JENKINS_AUTHS
#   HUBOT_JENKINS_IDS
#
#   URLs should be in the "http://jenkins1.example.com|http://jenkins2.example.com" format. 
#   Auth should be in the "user:password|user:password" format where the order of the credential pairs matches the jenkins instances
#   IDs should be in the "1|2" format where the order of the ID matches the jenkins instances
#
# Commands:
#   hubot jenkins <ID> b <jobNumber> - builds the job specified by jobNumber. List jobs to get number. The ID must match an entry in HUBOT_JENKINS_IDS
#   hubot jenkins <ID> build <job> - builds the specified Jenkins job. The ID must match an entry in HUBOT_JENKINS_IDS
#   hubot jenkins <ID> build <job>, <params> - builds the specified Jenkins job with parameters as key=value&key2=value2 The ID must match an entry in HUBOT_JENKINS_IDS
#   hubot jenkins <ID> list <filter> - lists Jenkins jobs. The ID must match an entry in HUBOT_JENKINS_IDS
#   hubot jenkins <ID> describe <job> - Describes the specified Jenkins job. The ID must match an entry in HUBOT_JENKINS_IDS
#   hubot jenkins <ID> last <job> - Details about the last build for the specified Jenkins job. The ID must match an entry in HUBOT_JENKINS_IDS
#   hubot jenkins <ID> changelog <job>, <buildnumber> - Changelog for the specified Jenkins job and build number.
#
# Author:
#   dougcole

querystring = require 'querystring'

# Holds a list of jobs, so we can trigger them with a number
# instead of the job's name. Gets populated on when calling
# list.
jobList = []

# Allow more than one instance of Jenkins to be accessed from the same bot
jenkinsEnvURL = {}
jenkinsEnvAuth = {}

loadConfig = (msg) ->
  
  urls = process.env.HUBOT_JENKINS_URLS.split "|"
  auths = process.env.HUBOT_JENKINS_AUTHS.split "|"
  ids = process.env.HUBOT_JENKINS_IDS.split "|"
  
  if urls.length != ids.length or auths.length != ids.length
    msg.reply "I can't tell which Jenkins to use. There is a mismatch in my configuration for how many environments you have."
  
  for id in ids
    idx = ids.indexOf(id)
  
    jenkinsEnvURL[id] = urls[idx]
    jenkinsEnvAuth[id] = auths[idx]

whichURL = (msg, env) ->
  
  if Object.keys(jenkinsEnvURL).length == 0
    loadConfig(msg)
  
  return jenkinsEnvURL[env]

whichAuth = (msg, env) ->
  
  if Object.keys(jenkinsEnvAuth).length == 0
    loadConfig(msg)
    
  return jenkinsEnvAuth[env]

jenkinsBuildById = (msg) ->
  # Switch the index with the job name
  job = jobList[parseInt(msg.match[1]) - 1]

  if job
    msg.match[1] = job
    jenkinsBuild(msg)
  else
    msg.reply "I couldn't find that job. Try `jenkins list` to get a list."

jenkinsBuild = (msg, buildWithEmptyParameters) ->
    env = querystring.escape msg.match[1]
    url = whichURL(msg, env)
    job = querystring.escape msg.match[2]
    params = msg.match[4]
    command = if buildWithEmptyParameters then "buildWithParameters" else "build"
    path = if params then "#{url}/job/#{job}/buildWithParameters?#{params}" else "#{url}/job/#{job}/#{command}"

    req = msg.http(path)

    if whichAuth(msg, env)
      auth = new Buffer(whichAuth(msg, env)).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.post() (err, res, body) ->
        if err
          msg.reply "Jenkins says: #{err}"
        else if 200 <= res.statusCode < 400 # Or, not an error code.
          msg.reply "(#{res.statusCode}) Build started for #{job} #{url}/job/#{job}"
        else if 400 == res.statusCode
          jenkinsBuild(msg, true)
        else
          msg.reply "Jenkins says: Status #{res.statusCode} #{body}"

jenkinsDescribe = (msg) ->
    env = querystring.escape msg.match[1]
    url = whichURL(msg, env)
    job = msg.match[2]

    path = "#{url}/job/#{job}/api/json"

    req = msg.http(path)

    if whichAuth(msg, env)
      auth = new Buffer(whichAuth(msg, env)).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.get() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else
          response = ""
          try
            content = JSON.parse(body)
            response += "JOB: #{content.displayName}\n"
            response += "URL: #{content.url}\n"

            if content.description
              response += "DESCRIPTION: #{content.description}\n"

            response += "ENABLED: #{content.buildable}\n"
            response += "STATUS: #{content.color}\n"

            tmpReport = ""
            if content.healthReport.length > 0
              for report in content.healthReport
                tmpReport += "\n  #{report.description}"
            else
              tmpReport = " unknown"
            response += "HEALTH: #{tmpReport}\n"

            parameters = ""
            for item in content.actions
              if item.parameterDefinitions
                for param in item.parameterDefinitions
                  tmpDescription = if param.description then " - #{param.description} " else ""
                  tmpDefault = if param.defaultParameterValue then " (default=#{param.defaultParameterValue.value})" else ""
                  parameters += "\n  #{param.name}#{tmpDescription}#{tmpDefault}"

            if parameters != ""
              response += "PARAMETERS: #{parameters}\n"

            msg.send response

            if not content.lastBuild
              return

            path = "#{url}/job/#{job}/#{content.lastBuild.number}/api/json"
            req = msg.http(path)
            if whichAuth(msg, env)
              auth = new Buffer(whichAuth(msg, env)).toString('base64')
              req.headers Authorization: "Basic #{auth}"

            req.header('Content-Length', 0)
            req.get() (err, res, body) ->
                if err
                  msg.send "Jenkins says: #{err}"
                else
                  response = ""
                  try
                    content = JSON.parse(body)
                    console.log(JSON.stringify(content, null, 4))
                    jobstatus = content.result || 'PENDING'
                    jobdate = new Date(content.timestamp);
                    response += "LAST JOB: #{jobstatus}, #{jobdate}\n"

                    msg.send response
                  catch error
                    msg.send error

          catch error
            msg.send error

jenkinsLast = (msg) ->
    env = querystring.escape msg.match[1]
    url = whichURL(msg, env)
    job = msg.match[2]

    path = "#{url}/job/#{job}/lastBuild/api/json"

    req = msg.http(path)

    if whichAuth(msg, env)
      auth = new Buffer(whichAuth(msg, env)).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.get() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else
          response = ""
          try
            content = JSON.parse(body)
            response += "NAME: #{content.fullDisplayName}\n"
            response += "URL: #{content.url}\n"

            if content.description
              response += "DESCRIPTION: #{content.description}\n"

            response += "BUILDING: #{content.building}\n"

            msg.send response

jenkinsList = (msg) ->
    env = querystring.escape msg.match[1]
    url = whichURL(msg, env)
    filter = new RegExp(msg.match[3], 'i')
    req = msg.http("#{url}/api/json")

    if whichAuth(msg, env)
      auth = new Buffer(whichAuth(msg, env)).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.get() (err, res, body) ->
        response = ""
        if err
          msg.send "Jenkins says: #{err}"
        else
          try
            content = JSON.parse(body)
            for job in content.jobs
              # Add the job to the jobList
              index = jobList.indexOf(job.name)
              if index == -1
                jobList.push(job.name)
                index = jobList.indexOf(job.name)

              state = if job.color == "red" then "FAIL" else "PASS"
              if filter.test job.name
                response += "[#{index + 1}] #{state} #{job.name}\n"
            msg.send response
          catch error
            msg.send error

jenkinsChangelog = (msg) ->
    env = querystring.escape msg.match[1]
    url = whichURL(msg, env)
    job = querystring.escape msg.match[2]
    buildNumber = msg.match[4]

    path = "#{url}/job/#{job}/#{buildNumber}/api/json"

    req = msg.http(path)

    if whichAuth(msg, env)
      auth = new Buffer(whichAuth(msg, env)).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.get() (err, res, body) ->
      if err
        msg.send "Jenkins says: #{err}"
      else
        response = "Changelog for #{job} build #{buildNumber}:\n\n"
        try

          content = JSON.parse(body)

          for item in content.changeSet.items
            response += "* #{item.msg}\n"

          msg.reply(response)
        catch e
          msg.send e

module.exports = (robot) ->
  robot.respond /j(?:enkins)? ([\w\.\-_ ]+) b(?:uild)? ([\w\.\-_ ]+)(, (.+))?/i, (msg) ->
    jenkinsBuild(msg, false)

  robot.respond /j(?:enkins)? ([\w\.\-_ ]+) b (\d+)/i, (msg) ->
    jenkinsBuildById(msg)

  robot.respond /j(?:enkins)? ([\w\.\-_ ]+) list( (.+))?/i, (msg) ->
    jenkinsList(msg)

  robot.respond /j(?:enkins)? ([\w\.\-_ ]+) describe (.*)/i, (msg) ->
    jenkinsDescribe(msg)

  robot.respond /j(?:enkins)? ([\w\.\-_ ]+) last (.*)/i, (msg) ->
    jenkinsLast(msg)

  robot.respond /j(?:enkins)? ([\w\.\-_ ]+) changelog ([\w\.\-_ ]+)(, (.+))?/i, (msg) ->
    jenkinsChangelog(msg)

  robot.jenkins = {
    list: jenkinsList,
    build: jenkinsBuild
    describe: jenkinsDescribe
    last: jenkinsLast
    changelog: jenkinsChangelog
  }
